from fastapi import APIRouter, Depends, HTTPException, status, Query, Request, WebSocket, WebSocketDisconnect
from typing import List
import json
import logging

from schemas.message import MessageCreate, MessageResponse
from services.auth import get_current_user

logger = logging.getLogger(__name__)


# WebSocket connection manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: dict[str, WebSocket] = {}  # user_id -> websocket

    async def connect(self, user_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[user_id] = websocket
        # Broadcast online status to all connected users
        await self._broadcast_presence(user_id, online=True)

    async def disconnect(self, user_id: str):
        self.active_connections.pop(user_id, None)
        # Broadcast offline status to all connected users
        await self._broadcast_presence(user_id, online=False)

    async def _broadcast_presence(self, user_id: str, online: bool):
        """Notify all other connected users about this user's presence change."""
        event = {
            "type": "online" if online else "offline",
            "user_id": user_id,
        }
        for uid, ws in list(self.active_connections.items()):
            if uid != user_id:
                try:
                    await ws.send_json(event)
                except Exception:
                    # Connection dead, will be cleaned up on next message
                    pass

    async def send_to_user(self, user_id: str, message: dict):
        ws = self.active_connections.get(user_id)
        if ws:
            try:
                await ws.send_json(message)
            except Exception:
                self.active_connections.pop(user_id, None)

    def is_online(self, user_id: str) -> bool:
        return user_id in self.active_connections


manager = ConnectionManager()

router = APIRouter(prefix="/api/messages", tags=["messages"])


@router.post("", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
async def send_message(
    message_data: MessageCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    sender_id = current_user["id"]

    # Validate receiver exists
    try:
        receiver = await pool.fetchrow("SELECT id, name FROM users WHERE id = $1", message_data.receiver_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid receiver ID format",
        )

    if not receiver:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Receiver not found",
        )

    if sender_id == message_data.receiver_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot send message to yourself",
        )

    # Check friendship OR shared community membership
    friendship = await pool.fetchrow(
        """SELECT id FROM friendships
           WHERE status = 'accepted'
           AND ((requester_id = $1 AND addressee_id = $2) OR (requester_id = $2 AND addressee_id = $1))""",
        sender_id, message_data.receiver_id
    )
    if not friendship:
        # Allow messaging if both are in the same community
        shared_community = await pool.fetchrow(
            """SELECT cm1.community_id FROM community_members cm1
               JOIN community_members cm2 ON cm1.community_id = cm2.community_id
               WHERE cm1.user_id = $1 AND cm2.user_id = $2
               AND cm1.status = 'active' AND cm2.status = 'active'
               LIMIT 1""",
            sender_id, message_data.receiver_id
        )
        if not shared_community:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You can only message friends or community members")

    # Determine initial status: 'delivered' if receiver is online, 'sent' otherwise
    initial_status = 'delivered' if manager.is_online(message_data.receiver_id) else 'sent'

    try:
        row = await pool.fetchrow(
            """
            INSERT INTO messages (sender_id, receiver_id, message, image_url, message_type, status)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING *
            """,
            sender_id,
            message_data.receiver_id,
            message_data.message,
            message_data.image_url,
            message_data.message_type,
            initial_status,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to send message: {str(e)}",
        )

    msg_status = row.get("status") or initial_status

    response_data = MessageResponse(
        id=str(row["id"]),
        sender_id=str(row["sender_id"]),
        receiver_id=str(row["receiver_id"]),
        message=row["message"],
        timestamp=row["timestamp"],
        is_read=row["is_read"],
        status=msg_status,
        sender_name=current_user["name"],
        image_url=row["image_url"] or "",
        message_type=row["message_type"] or "text",
    )

    # Broadcast via WebSocket to both sender and receiver for real-time updates
    ws_payload = {
        "type": "message",
        "id": response_data.id,
        "sender_id": response_data.sender_id,
        "receiver_id": response_data.receiver_id,
        "message": response_data.message,
        "timestamp": response_data.timestamp.isoformat(),
        "is_read": response_data.is_read,
        "status": response_data.status,
        "sender_name": response_data.sender_name or "",
        "image_url": response_data.image_url,
        "message_type": response_data.message_type,
    }
    # Send to receiver (real-time delivery)
    await manager.send_to_user(message_data.receiver_id, ws_payload)
    # Send to sender (so other devices / the WS listener can confirm)
    await manager.send_to_user(sender_id, ws_payload)

    return response_data


@router.post("/{user_id}/read")
async def mark_messages_read(
    user_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Mark all messages from user_id to current user as read (REST fallback for WebSocket read receipts)."""
    pool = request.app.state.pool
    my_id = current_user["id"]
    await pool.execute(
        "UPDATE messages SET is_read = TRUE, status = 'read' WHERE sender_id = $1 AND receiver_id = $2 AND status != 'read'",
        user_id,
        my_id,
    )
    return {"status": "ok"}


@router.get("/unread-count")
async def get_unread_count(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    current_id = current_user["id"]

    count = await pool.fetchval(
        "SELECT COUNT(*) FROM messages WHERE receiver_id = $1 AND is_read = FALSE",
        current_id,
    )
    return {"count": count or 0}


@router.get("/online/{user_id}")
async def check_online(user_id: str, current_user: dict = Depends(get_current_user)):
    return {"online": manager.is_online(user_id)}


@router.get("/{user_id}", response_model=List[MessageResponse])
async def get_conversation(
    user_id: str,
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    current_id = current_user["id"]

    # Validate the other user exists
    try:
        other_user = await pool.fetchrow("SELECT id, name FROM users WHERE id = $1", user_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid user ID format",
        )

    if not other_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    # Mark messages from other user as read (update both is_read and status)
    await pool.execute(
        """
        UPDATE messages SET is_read = TRUE, status = 'read'
        WHERE sender_id = $1 AND receiver_id = $2 AND status != 'read'
        """,
        user_id,
        current_id,
    )

    # Fetch conversation
    rows = await pool.fetch(
        """
        SELECT m.*,
               u.name AS sender_name
        FROM messages m
        JOIN users u ON m.sender_id = u.id
        WHERE (m.sender_id = $1 AND m.receiver_id = $2)
           OR (m.sender_id = $2 AND m.receiver_id = $1)
        ORDER BY m.timestamp ASC
        OFFSET $3 LIMIT $4
        """,
        current_id,
        user_id,
        skip,
        limit,
    )

    return [
        MessageResponse(
            id=str(row["id"]),
            sender_id=str(row["sender_id"]),
            receiver_id=str(row["receiver_id"]),
            message=row["message"],
            timestamp=row["timestamp"],
            is_read=row["is_read"],
            status=row.get("status") or ("read" if row["is_read"] else "sent"),
            sender_name=row["sender_name"],
            image_url=row.get("image_url") or "",
            message_type=row.get("message_type") or "text",
        )
        for row in rows
    ]


@router.get("")
async def get_conversations(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    current_id = current_user["id"]

    # Get the latest message per conversation partner with unread count
    rows = await pool.fetch(
        """
        WITH conversation_messages AS (
            SELECT m.*,
                   CASE WHEN m.sender_id = $1 THEN m.receiver_id ELSE m.sender_id END AS partner_id
            FROM messages m
            WHERE m.sender_id = $1 OR m.receiver_id = $1
        )
        SELECT DISTINCT ON (cm.partner_id)
               cm.partner_id,
               cm.message,
               cm.timestamp,
               u.name AS partner_name,
               u.profile_image_url AS partner_image
        FROM conversation_messages cm
        JOIN users u ON cm.partner_id = u.id
        ORDER BY cm.partner_id, cm.timestamp DESC
        """,
        current_id,
    )

    # Get unread counts per partner
    unread_rows = await pool.fetch(
        """
        SELECT sender_id, COUNT(*) AS unread
        FROM messages
        WHERE receiver_id = $1 AND is_read = FALSE
        GROUP BY sender_id
        """,
        current_id,
    )
    unread_map = {str(r["sender_id"]): r["unread"] for r in unread_rows}

    # Sort by timestamp descending
    sorted_rows = sorted(rows, key=lambda r: r["timestamp"], reverse=True)

    # Build DM conversations
    conversations = []
    for row in sorted_rows:
        pid = str(row["partner_id"])
        conversations.append({
            "type": "dm",
            "user_id": pid,
            "user_name": row["partner_name"],
            "user_image": row["partner_image"] or None,
            "last_message": row["message"],
            "last_message_time": row["timestamp"].isoformat(),
            "unread_count": unread_map.get(pid, 0),
        })

    # Get community groups the user is a member of that have messages
    community_rows = await pool.fetch(
        """
        SELECT c.id, c.name, c.image_url,
               (SELECT cm2.message FROM community_messages cm2
                WHERE cm2.community_id = c.id ORDER BY cm2.timestamp DESC LIMIT 1) AS last_msg,
               (SELECT cm2.timestamp FROM community_messages cm2
                WHERE cm2.community_id = c.id ORDER BY cm2.timestamp DESC LIMIT 1) AS last_ts
        FROM communities c
        JOIN community_members mem ON mem.community_id = c.id AND mem.user_id = $1 AND mem.status = 'active'
        ORDER BY last_ts DESC NULLS LAST
        """,
        current_id,
    )

    for row in community_rows:
        conversations.append({
            "type": "community",
            "user_id": str(row["id"]),
            "user_name": row["name"],
            "user_image": row["image_url"] or None,
            "last_message": row["last_msg"] or "",
            "last_message_time": row["last_ts"].isoformat() if row["last_ts"] else None,
            "unread_count": 0,
        })

    # Get ALL sub-groups the user is a member of (show even without messages)
    subgroup_rows = await pool.fetch(
        """
        SELECT sg.id, sg.name, sg.community_id, c.name AS community_name, c.image_url AS community_image,
               (SELECT sgm2.message FROM sub_group_messages sgm2
                WHERE sgm2.sub_group_id = sg.id ORDER BY sgm2.timestamp DESC LIMIT 1) AS last_msg,
               (SELECT sgm2.timestamp FROM sub_group_messages sgm2
                WHERE sgm2.sub_group_id = sg.id ORDER BY sgm2.timestamp DESC LIMIT 1) AS last_ts
        FROM sub_groups sg
        JOIN sub_group_members sgmem ON sgmem.sub_group_id = sg.id AND sgmem.user_id = $1
        JOIN communities c ON sg.community_id = c.id
        ORDER BY last_ts DESC NULLS LAST
        """,
        current_id,
    )

    for row in subgroup_rows:
        conversations.append({
            "type": "community",
            "user_id": str(row["id"]),
            "user_name": row["name"],
            "user_image": row["community_image"] or None,
            "last_message": row["last_msg"] or "",
            "last_message_time": row["last_ts"].isoformat() if row["last_ts"] else None,
            "unread_count": 0,
            "is_subgroup": True,
            "community_id": str(row["community_id"]),
            "community_name": row["community_name"],
        })

    # Sort all by last_message_time
    conversations.sort(
        key=lambda x: x.get("last_message_time") or "2000-01-01",
        reverse=True,
    )

    return conversations


@router.put("/{message_id}")
async def edit_message(
    message_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Edit own message text."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    body = await request.json()
    new_text = body.get("message", "").strip()
    if not new_text:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Message text cannot be empty")

    msg = await pool.fetchrow(
        "SELECT * FROM messages WHERE id = $1 AND sender_id = $2",
        message_id, user_id,
    )
    if not msg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found or not yours")

    await pool.execute(
        "UPDATE messages SET message = $1 WHERE id = $2",
        new_text, message_id,
    )
    return {"status": "ok", "message": new_text}


@router.delete("/{message_id}")
async def delete_message(
    message_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Delete own message for everyone."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    msg = await pool.fetchrow(
        "SELECT * FROM messages WHERE id = $1 AND sender_id = $2",
        message_id, user_id,
    )
    if not msg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found or not yours")

    await pool.execute("DELETE FROM messages WHERE id = $1", message_id)
    return {"status": "ok"}


@router.websocket("/ws/{token}")
async def websocket_chat(websocket: WebSocket, token: str):
    from services.auth import decode_access_token

    payload = decode_access_token(token)
    if not payload:
        await websocket.close(code=4001)
        return

    user_id = payload.get("sub")
    if not user_id:
        await websocket.close(code=4001)
        return

    pool = websocket.app.state.pool

    # Verify user exists
    user = await pool.fetchrow(
        "SELECT id, name, profile_image_url FROM users WHERE id = $1", user_id
    )
    if not user:
        await websocket.close(code=4001)
        return

    await manager.connect(user_id, websocket)

    # When user connects, mark pending/sent messages TO them as delivered
    try:
        undelivered = await pool.fetch(
            "UPDATE messages SET status = 'delivered' WHERE receiver_id = $1 AND status = 'sent' RETURNING sender_id",
            user_id
        )
        # Notify senders their messages were delivered
        notified_senders = set()
        for row in undelivered:
            sender_id = str(row['sender_id'])
            if sender_id not in notified_senders:
                notified_senders.add(sender_id)
                await manager.send_to_user(
                    sender_id,
                    {"type": "delivered", "user_id": user_id}
                )
    except Exception as e:
        logger.warning(f"Failed to mark messages as delivered on connect: {e}")

    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type", "message")

            if msg_type == "message":
                receiver_id = data.get("receiver_id")
                message_text = data.get("message", "")
                image_url = data.get("image_url", "")
                ws_message_type = data.get("message_type", "text")

                if not receiver_id or (not message_text and not image_url):
                    continue

                # Check friendship
                friendship = await pool.fetchrow(
                    """SELECT id FROM friendships
                       WHERE status = 'accepted'
                       AND ((requester_id = $1 AND addressee_id = $2) OR (requester_id = $2 AND addressee_id = $1))""",
                    user_id,
                    receiver_id,
                )
                if not friendship:
                    await websocket.send_json(
                        {"type": "error", "message": "You can only message friends"}
                    )
                    continue

                # Determine initial status
                initial_status = 'delivered' if manager.is_online(receiver_id) else 'sent'

                # Save to DB
                row = await pool.fetchrow(
                    """INSERT INTO messages (sender_id, receiver_id, message, image_url, message_type, status)
                       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *""",
                    user_id,
                    receiver_id,
                    message_text,
                    image_url,
                    ws_message_type,
                    initial_status,
                )

                msg_status = row.get("status") or initial_status

                msg_response = {
                    "type": "message",
                    "id": str(row["id"]),
                    "sender_id": user_id,
                    "receiver_id": receiver_id,
                    "message": row["message"],
                    "timestamp": row["timestamp"].isoformat(),
                    "is_read": False,
                    "status": msg_status,
                    "sender_name": user["name"],
                    "sender_image": user.get("profile_image_url") or "",
                    "image_url": row["image_url"] or "",
                    "message_type": row["message_type"] or "text",
                }

                # Send to receiver if online
                await manager.send_to_user(receiver_id, msg_response)
                # Send confirmation back to sender
                await websocket.send_json(msg_response)

            elif msg_type == "read":
                # Mark messages as read
                sender_id = data.get("sender_id")
                if sender_id:
                    # Get IDs of messages being marked as read (for client-side update)
                    unread_rows = await pool.fetch(
                        "SELECT id FROM messages WHERE sender_id = $1 AND receiver_id = $2 AND status != 'read'",
                        sender_id,
                        user_id,
                    )
                    read_message_ids = [str(r["id"]) for r in unread_rows]

                    # Update both is_read and status
                    await pool.execute(
                        "UPDATE messages SET is_read = TRUE, status = 'read' WHERE sender_id = $1 AND receiver_id = $2 AND status != 'read'",
                        sender_id,
                        user_id,
                    )
                    # Notify the sender that their messages were read
                    await manager.send_to_user(
                        sender_id,
                        {
                            "type": "read_receipt",
                            "reader_id": user_id,
                            "message_ids": read_message_ids,
                        },
                    )

            elif msg_type == "typing":
                receiver_id = data.get("receiver_id")
                if receiver_id:
                    await manager.send_to_user(
                        receiver_id,
                        {
                            "type": "typing",
                            "sender_id": user_id,
                            "sender_name": user["name"],
                        },
                    )

    except WebSocketDisconnect:
        await manager.disconnect(user_id)
    except Exception:
        await manager.disconnect(user_id)
