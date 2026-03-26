from fastapi import APIRouter, Depends, HTTPException, status, Request
from typing import List

from schemas.friend import FriendRequestCreate, FriendRequestResponse, FriendResponse, FriendshipStatus
from services.auth import get_current_user

router = APIRouter(prefix="/api/friends", tags=["friends"])


@router.post("/request", response_model=FriendRequestResponse, status_code=status.HTTP_201_CREATED)
async def send_friend_request(
    data: FriendRequestCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    if user_id == data.addressee_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot send friend request to yourself",
        )

    # Check addressee exists
    try:
        addressee = await pool.fetchrow("SELECT id, name, profile_image_url FROM users WHERE id = $1", data.addressee_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user ID format")

    if not addressee:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    # Check if friendship already exists in either direction
    existing = await pool.fetchrow(
        """SELECT id, status FROM friendships
           WHERE (requester_id = $1 AND addressee_id = $2)
              OR (requester_id = $2 AND addressee_id = $1)""",
        user_id, data.addressee_id
    )

    if existing:
        if existing["status"] == "accepted":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Already friends")
        elif existing["status"] == "pending":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Friend request already pending")

    try:
        row = await pool.fetchrow(
            """INSERT INTO friendships (requester_id, addressee_id, status)
               VALUES ($1, $2, 'pending')
               RETURNING *""",
            user_id, data.addressee_id
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to send friend request: {str(e)}",
        )

    return FriendRequestResponse(
        id=str(row["id"]),
        requester_id=str(row["requester_id"]),
        addressee_id=str(row["addressee_id"]),
        status=row["status"],
        requester_name=current_user["name"],
        requester_image=current_user.get("profile_image_url"),
        addressee_name=addressee["name"],
        addressee_image=addressee.get("profile_image_url"),
        created_at=row["created_at"],
    )


@router.post("/accept/{request_id}", response_model=FriendRequestResponse)
async def accept_friend_request(
    request_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        freq = await pool.fetchrow(
            "SELECT * FROM friendships WHERE id = $1 AND addressee_id = $2 AND status = 'pending'",
            request_id, user_id
        )
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid request ID format")

    if not freq:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Friend request not found")

    row = await pool.fetchrow(
        """UPDATE friendships SET status = 'accepted', updated_at = NOW()
           WHERE id = $1 RETURNING *""",
        request_id
    )

    requester = await pool.fetchrow(
        "SELECT name, profile_image_url FROM users WHERE id = $1",
        str(row["requester_id"])
    )

    return FriendRequestResponse(
        id=str(row["id"]),
        requester_id=str(row["requester_id"]),
        addressee_id=str(row["addressee_id"]),
        status=row["status"],
        requester_name=requester["name"] if requester else None,
        requester_image=requester.get("profile_image_url") if requester else None,
        addressee_name=current_user["name"],
        addressee_image=current_user.get("profile_image_url"),
        created_at=row["created_at"],
    )


@router.post("/reject/{request_id}", response_model=FriendRequestResponse)
async def reject_friend_request(
    request_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        freq = await pool.fetchrow(
            "SELECT * FROM friendships WHERE id = $1 AND addressee_id = $2 AND status = 'pending'",
            request_id, user_id
        )
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid request ID format")

    if not freq:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Friend request not found")

    row = await pool.fetchrow(
        """UPDATE friendships SET status = 'rejected', updated_at = NOW()
           WHERE id = $1 RETURNING *""",
        request_id
    )

    requester = await pool.fetchrow(
        "SELECT name, profile_image_url FROM users WHERE id = $1",
        str(row["requester_id"])
    )

    return FriendRequestResponse(
        id=str(row["id"]),
        requester_id=str(row["requester_id"]),
        addressee_id=str(row["addressee_id"]),
        status=row["status"],
        requester_name=requester["name"] if requester else None,
        requester_image=requester.get("profile_image_url") if requester else None,
        addressee_name=current_user["name"],
        addressee_image=current_user.get("profile_image_url"),
        created_at=row["created_at"],
    )


@router.delete("/{user_id}", status_code=status.HTTP_200_OK)
async def unfriend(
    user_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    current_id = current_user["id"]

    try:
        result = await pool.execute(
            """DELETE FROM friendships
               WHERE status = 'accepted'
               AND ((requester_id = $1 AND addressee_id = $2) OR (requester_id = $2 AND addressee_id = $1))""",
            current_id, user_id
        )
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user ID format")

    if result == "DELETE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Friendship not found")

    return {"detail": "Unfriended successfully"}


@router.get("", response_model=List[FriendResponse])
async def list_friends(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """SELECT u.id, u.name, u.email, u.bio, u.profile_image_url, u.interests
           FROM friendships f
           JOIN users u ON (
               CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END = u.id
           )
           WHERE f.status = 'accepted'
           AND (f.requester_id = $1 OR f.addressee_id = $1)
           ORDER BY u.name ASC""",
        user_id
    )

    return [
        FriendResponse(
            id=str(row["id"]),
            name=row["name"],
            email=row["email"],
            bio=row["bio"] or "",
            profile_image_url=row["profile_image_url"] or None,
            interests=row["interests"] or [],
        )
        for row in rows
    ]


@router.get("/requests", response_model=List[FriendRequestResponse])
async def get_pending_requests(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """SELECT f.*,
                  req.name AS requester_name, req.profile_image_url AS requester_image,
                  addr.name AS addressee_name, addr.profile_image_url AS addressee_image
           FROM friendships f
           JOIN users req ON f.requester_id = req.id
           JOIN users addr ON f.addressee_id = addr.id
           WHERE f.addressee_id = $1 AND f.status = 'pending'
           ORDER BY f.created_at DESC""",
        user_id
    )

    return [
        FriendRequestResponse(
            id=str(row["id"]),
            requester_id=str(row["requester_id"]),
            addressee_id=str(row["addressee_id"]),
            status=row["status"],
            requester_name=row["requester_name"],
            requester_image=row.get("requester_image"),
            addressee_name=row["addressee_name"],
            addressee_image=row.get("addressee_image"),
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.get("/sent", response_model=List[FriendRequestResponse])
async def get_sent_requests(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """SELECT f.*,
                  req.name AS requester_name, req.profile_image_url AS requester_image,
                  addr.name AS addressee_name, addr.profile_image_url AS addressee_image
           FROM friendships f
           JOIN users req ON f.requester_id = req.id
           JOIN users addr ON f.addressee_id = addr.id
           WHERE f.requester_id = $1 AND f.status = 'pending'
           ORDER BY f.created_at DESC""",
        user_id
    )

    return [
        FriendRequestResponse(
            id=str(row["id"]),
            requester_id=str(row["requester_id"]),
            addressee_id=str(row["addressee_id"]),
            status=row["status"],
            requester_name=row["requester_name"],
            requester_image=row.get("requester_image"),
            addressee_name=row["addressee_name"],
            addressee_image=row.get("addressee_image"),
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.get("/status/{user_id}", response_model=FriendshipStatus)
async def get_friendship_status(
    user_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    current_id = current_user["id"]

    try:
        row = await pool.fetchrow(
            """SELECT id, requester_id, addressee_id, status FROM friendships
               WHERE (requester_id = $1 AND addressee_id = $2)
                  OR (requester_id = $2 AND addressee_id = $1)""",
            current_id, user_id
        )
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user ID format")

    if not row:
        return FriendshipStatus(status="none")

    if row["status"] == "accepted":
        return FriendshipStatus(status="friends", request_id=str(row["id"]))

    if row["status"] == "pending":
        if str(row["requester_id"]) == current_id:
            return FriendshipStatus(status="pending_sent", request_id=str(row["id"]))
        else:
            return FriendshipStatus(status="pending_received", request_id=str(row["id"]))

    return FriendshipStatus(status="none")
