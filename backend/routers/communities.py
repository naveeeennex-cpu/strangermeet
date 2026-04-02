from fastapi import APIRouter, Depends, HTTPException, status, Query, Request
from typing import List, Optional
from routers.chat import manager as ws_manager

import math
import httpx
from schemas.community import (
    CommunityCreate, CommunityUpdate, CommunityResponse,
    CommunityPostCreate, CommunityPostResponse,
    CommunityPostCommentCreate, CommunityPostCommentResponse,
    SubGroupCreate, SubGroupResponse,
    CommunityMessageCreate, CommunityMessageResponse,
    SubGroupMessageCreate, SubGroupMessageResponse,
    CommunityEventCreate, CommunityEventResponse,
    CommunityEventBookingResponse,
    EventParticipantResponse,
    CommunityMemberResponse,
    SubGroupMemberResponse,
    ItineraryDayCreate, ItineraryDayResponse,
    EventRideCreate, EventRideResponse, EventRidePassengerResponse, JoinRideRequest,
)


GOOGLE_MAPS_API_KEY = "AIzaSyCRoRzp4kOtaSxQGKOBP4Ke8L1oe8Xn5zA"


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Fallback straight-line distance in km."""
    R = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


async def _road_distance_km(
    lat1: float, lng1: float,
    lat2: float, lng2: float,
    waypoints: Optional[list] = None,
) -> tuple[float, str]:
    """
    Returns (road_distance_km, encoded_polyline) using Google Directions API.
    Falls back to haversine + empty polyline on any error.
    """
    try:
        params = {
            "origin": f"{lat1},{lng1}",
            "destination": f"{lat2},{lng2}",
            "mode": "driving",
            "key": GOOGLE_MAPS_API_KEY,
        }
        if waypoints:
            params["waypoints"] = "|".join(f"{w[0]},{w[1]}" for w in waypoints)

        async with httpx.AsyncClient(timeout=8) as client:
            resp = await client.get(
                "https://maps.googleapis.com/maps/api/directions/json",
                params=params,
            )
        data = resp.json()
        if data.get("status") == "OK":
            leg = data["routes"][0]["legs"][0]
            dist_km = leg["distance"]["value"] / 1000.0
            polyline = data["routes"][0]["overview_polyline"]["points"]
            return round(dist_km, 2), polyline
    except Exception:
        pass
    # Fallback
    return round(_haversine_km(lat1, lng1, lat2, lng2), 2), ""


from services.auth import get_current_user

router = APIRouter(prefix="/api/communities", tags=["communities"])


# ── Helper: check memberships ────────────────────────────────────────────────

async def _get_membership(pool, community_id: str, user_id: str):
    try:
        return await pool.fetchrow(
            "SELECT * FROM community_members WHERE community_id = $1 AND user_id = $2 AND status = 'active'",
            community_id, user_id
        )
    except Exception:
        return None


async def _require_member(pool, community_id: str, user_id: str):
    member = await _get_membership(pool, community_id, user_id)
    if not member:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You must be a member of this community")
    return member


async def _require_admin(pool, community_id: str, user_id: str):
    member = await _get_membership(pool, community_id, user_id)
    if not member or member["role"] != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    return member


# ── CRUD: Communities ────────────────────────────────────────────────────────

@router.post("", response_model=CommunityResponse, status_code=status.HTTP_201_CREATED)
async def create_community(
    data: CommunityCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        row = await pool.fetchrow(
            """INSERT INTO communities (name, description, image_url, category, is_private, created_by, members_count)
               VALUES ($1, $2, $3, $4, $5, $6, 1)
               RETURNING *""",
            data.name, data.description, data.image_url, data.category, data.is_private, user_id
        )
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to create community: {str(e)}")

    community_id = str(row["id"])

    # Add creator as admin member
    await pool.execute(
        "INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1, $2, 'admin', 'active')",
        community_id, user_id
    )

    return CommunityResponse(
        id=community_id,
        name=row["name"],
        description=row["description"],
        image_url=row["image_url"],
        category=row["category"],
        is_private=row["is_private"],
        created_by=str(row["created_by"]),
        creator_name=current_user["name"],
        members_count=row["members_count"],
        is_member=True,
        member_role="admin",
        created_at=row["created_at"],
    )


@router.get("", response_model=List[CommunityResponse])
async def list_communities(
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    category: str = Query("", description="Filter by category"),
    search: str = Query("", description="Search by name"),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    query = """
        SELECT c.*, u.name AS creator_name,
               cm.role AS member_role, cm.status AS member_status
        FROM communities c
        JOIN users u ON c.created_by = u.id
        LEFT JOIN community_members cm ON cm.community_id = c.id AND cm.user_id = $1
        WHERE 1=1
    """
    params = [user_id]
    idx = 2

    if category:
        query += f" AND c.category = ${idx}"
        params.append(category)
        idx += 1

    if search:
        query += f" AND c.name ILIKE ${idx}"
        params.append(f"%{search}%")
        idx += 1

    query += f" ORDER BY c.created_at DESC OFFSET ${idx} LIMIT ${idx + 1}"
    params.extend([skip, limit])

    rows = await pool.fetch(query, *params)

    return [
        CommunityResponse(
            id=str(row["id"]),
            name=row["name"],
            description=row["description"],
            image_url=row["image_url"],
            category=row["category"],
            is_private=row["is_private"],
            created_by=str(row["created_by"]),
            creator_name=row["creator_name"],
            members_count=row["members_count"],
            is_member=row["member_role"] is not None and row["member_status"] == "active",
            member_role=row["member_role"] if row["member_status"] == "active" else None,
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.get("/my", response_model=List[CommunityResponse])
async def my_communities(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """SELECT c.*, u.name AS creator_name,
                  cm.role AS member_role, cm.status AS member_status
           FROM communities c
           JOIN users u ON c.created_by = u.id
           JOIN community_members cm ON cm.community_id = c.id AND cm.user_id = $1 AND cm.status = 'active'
           ORDER BY c.created_at DESC""",
        user_id
    )

    return [
        CommunityResponse(
            id=str(row["id"]),
            name=row["name"],
            description=row["description"],
            image_url=row["image_url"],
            category=row["category"],
            is_private=row["is_private"],
            created_by=str(row["created_by"]),
            creator_name=row["creator_name"],
            members_count=row["members_count"],
            is_member=True,
            member_role=row["member_role"],
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.get("/count/{user_id}")
async def community_count(
    user_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    try:
        count = await pool.fetchval(
            "SELECT COUNT(*) FROM community_members WHERE user_id = $1 AND status = 'active'",
            user_id
        )
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user ID format")

    return {"count": count or 0}


@router.get("/joined")
async def my_joined_communities(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Get communities the current user has joined."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """SELECT c.id, c.name, c.description, c.image_url, c.category,
                  c.is_private, c.members_count, c.created_at
           FROM communities c
           JOIN community_members cm ON c.id = cm.community_id
           WHERE cm.user_id = $1 AND cm.status = 'active'
           ORDER BY cm.joined_at DESC""",
        user_id
    )

    return [
        {
            "id": str(row["id"]),
            "name": row["name"],
            "description": row["description"],
            "image_url": row["image_url"],
            "category": row["category"],
            "is_private": row["is_private"],
            "members_count": row["members_count"],
            "created_at": row["created_at"].isoformat() if row["created_at"] else None,
        }
        for row in rows
    ]


@router.get("/user/{user_id}/joined")
async def user_joined_communities(
    user_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Get list of communities a user has joined."""
    pool = request.app.state.pool

    try:
        rows = await pool.fetch(
            """SELECT c.id, c.name, c.description, c.image_url, c.category,
                      c.is_private, c.members_count, c.created_at
               FROM communities c
               JOIN community_members cm ON c.id = cm.community_id
               WHERE cm.user_id = $1 AND cm.status = 'active'
               ORDER BY cm.joined_at DESC""",
            user_id
        )
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid user ID")

    return [
        {
            "id": str(row["id"]),
            "name": row["name"],
            "description": row["description"],
            "image_url": row["image_url"],
            "category": row["category"],
            "is_private": row["is_private"],
            "members_count": row["members_count"],
            "created_at": row["created_at"].isoformat() if row["created_at"] else None,
        }
        for row in rows
    ]


@router.get("/{community_id}", response_model=CommunityResponse)
async def get_community(
    community_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        row = await pool.fetchrow(
            """SELECT c.*, u.name AS creator_name, u.phone AS admin_phone,
                      u.profile_image_url AS creator_image,
                      cm.role AS member_role, cm.status AS member_status
               FROM communities c
               JOIN users u ON c.created_by = u.id
               LEFT JOIN community_members cm ON cm.community_id = c.id AND cm.user_id = $2
               WHERE c.id = $1""",
            community_id, user_id
        )
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid community ID format")

    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")

    return CommunityResponse(
        id=str(row["id"]),
        name=row["name"],
        description=row["description"],
        image_url=row["image_url"],
        category=row["category"],
        is_private=row["is_private"],
        created_by=str(row["created_by"]),
        creator_name=row["creator_name"],
        creator_image=row.get("creator_image") or None,
        admin_phone=row.get("admin_phone") or None,
        members_count=row["members_count"],
        is_member=row["member_role"] is not None and row.get("member_status") == "active",
        member_role=row["member_role"] if row.get("member_status") == "active" else None,
        created_at=row["created_at"],
    )


@router.put("/{community_id}", response_model=CommunityResponse)
async def update_community(
    community_id: str,
    data: CommunityUpdate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    updates = []
    params = []
    idx = 1
    for field in ["name", "description", "image_url", "category", "is_private"]:
        value = getattr(data, field)
        if value is not None:
            updates.append(f"{field} = ${idx}")
            params.append(value)
            idx += 1

    if not updates:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No fields to update")

    params.append(community_id)
    query = f"UPDATE communities SET {', '.join(updates)} WHERE id = ${idx} RETURNING *"

    row = await pool.fetchrow(query, *params)

    creator = await pool.fetchrow("SELECT name FROM users WHERE id = $1", str(row["created_by"]))

    return CommunityResponse(
        id=str(row["id"]),
        name=row["name"],
        description=row["description"],
        image_url=row["image_url"],
        category=row["category"],
        is_private=row["is_private"],
        created_by=str(row["created_by"]),
        creator_name=creator["name"] if creator else None,
        members_count=row["members_count"],
        is_member=True,
        member_role="admin",
        created_at=row["created_at"],
    )


@router.delete("/{community_id}", status_code=status.HTTP_200_OK)
async def delete_community(
    community_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    await pool.execute("DELETE FROM communities WHERE id = $1", community_id)
    return {"detail": "Community deleted successfully"}


# ── Join / Leave ─────────────────────────────────────────────────────────────

@router.post("/{community_id}/join", status_code=status.HTTP_200_OK)
async def join_community(
    community_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        community = await pool.fetchrow("SELECT id, is_private FROM communities WHERE id = $1", community_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid community ID format")

    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")

    # Check if kicked — must request admin to rejoin
    kicked = await pool.fetchrow(
        "SELECT id FROM community_members WHERE community_id = $1 AND user_id = $2 AND status = 'kicked'",
        community_id, user_id
    )
    if kicked:
        # Update status to pending (request to rejoin)
        await pool.execute(
            "UPDATE community_members SET status = 'pending' WHERE community_id = $1 AND user_id = $2 AND status = 'kicked'",
            community_id, user_id
        )
        return {"detail": "Rejoin request sent to admin", "status": "pending"}

    existing = await _get_membership(pool, community_id, user_id)
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Already a member")

    # Check if there's a pending membership
    pending = await pool.fetchrow(
        "SELECT id FROM community_members WHERE community_id = $1 AND user_id = $2 AND status = 'pending'",
        community_id, user_id
    )
    if pending:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Membership request already pending")

    member_status = "pending" if community["is_private"] else "active"

    await pool.execute(
        "INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1, $2, 'member', $3) ON CONFLICT DO NOTHING",
        community_id, user_id, member_status
    )

    if member_status == "active":
        await pool.execute(
            "UPDATE communities SET members_count = members_count + 1 WHERE id = $1",
            community_id
        )

    return {"detail": "Joined community" if member_status == "active" else "Membership request sent"}


@router.post("/{community_id}/leave", status_code=status.HTTP_200_OK)
async def leave_community(
    community_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    member = await _get_membership(pool, community_id, user_id)
    if not member:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Not a member")

    if member["role"] == "admin":
        # Check if there are other admins
        admin_count = await pool.fetchval(
            "SELECT COUNT(*) FROM community_members WHERE community_id = $1 AND role = 'admin' AND status = 'active'",
            community_id
        )
        if admin_count <= 1:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot leave as the only admin. Delete the community or assign another admin.")

    await pool.execute(
        "DELETE FROM community_members WHERE community_id = $1 AND user_id = $2",
        community_id, user_id
    )

    await pool.execute(
        "UPDATE communities SET members_count = GREATEST(members_count - 1, 0) WHERE id = $1",
        community_id
    )

    return {"detail": "Left community"}


# ── Members ──────────────────────────────────────────────────────────────────

@router.get("/{community_id}/members", response_model=List[CommunityMemberResponse])
async def list_members(
    community_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    rows = await pool.fetch(
        """SELECT cm.*, u.name AS user_name, u.email AS user_email, u.profile_image_url AS user_profile_image
           FROM community_members cm
           JOIN users u ON cm.user_id = u.id
           WHERE cm.community_id = $1 AND cm.status = 'active'
           ORDER BY cm.joined_at ASC""",
        community_id
    )

    return [
        CommunityMemberResponse(
            id=str(row["id"]),
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            user_email=row["user_email"],
            user_profile_image=row.get("user_profile_image"),
            role=row["role"],
            status=row["status"],
            joined_at=row["joined_at"],
        )
        for row in rows
    ]


# ── Community Posts ──────────────────────────────────────────────────────────

@router.post("/{community_id}/posts", response_model=CommunityPostResponse, status_code=status.HTTP_201_CREATED)
async def create_community_post(
    community_id: str,
    data: CommunityPostCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_member(pool, community_id, user_id)

    try:
        # Write to unified posts table with community_id set
        row = await pool.fetchrow(
            """INSERT INTO posts (user_id, image_url, caption, media_type, community_id)
               VALUES ($1, $2, $3, 'image', $4) RETURNING *""",
            user_id, data.image_url or "", data.caption, community_id
        )
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to create post: {str(e)}")

    return CommunityPostResponse(
        id=str(row["id"]),
        community_id=community_id,
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        user_profile_image=current_user.get("profile_image_url"),
        image_url=row["image_url"] or None,
        caption=row["caption"],
        likes_count=0,
        is_liked=False,
        comments_count=0,
        created_at=row["created_at"],
    )


@router.get("/{community_id}/posts", response_model=List[CommunityPostResponse])
async def list_community_posts(
    community_id: str,
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Read from unified posts table filtered by community_id
    rows = await pool.fetch(
        """SELECT p.*, u.name AS user_name, u.profile_image_url AS user_profile_image,
                  (SELECT COUNT(*) FROM comments WHERE post_id = p.id) AS comments_count
           FROM posts p
           JOIN users u ON p.user_id = u.id
           WHERE p.community_id = $1
           ORDER BY p.created_at DESC
           OFFSET $2 LIMIT $3""",
        community_id, skip, limit
    )

    if rows:
        post_ids = [row["id"] for row in rows]
        liked_rows = await pool.fetch(
            "SELECT post_id FROM post_likes WHERE user_id = $1 AND post_id = ANY($2)",
            user_id, post_ids
        )
        liked_ids = {str(r["post_id"]) for r in liked_rows}
    else:
        liked_ids = set()

    return [
        CommunityPostResponse(
            id=str(row["id"]),
            community_id=community_id,
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            user_profile_image=row.get("user_profile_image"),
            image_url=row["image_url"] or None,
            caption=row["caption"],
            likes_count=row["likes_count"],
            is_liked=str(row["id"]) in liked_ids,
            comments_count=row.get("comments_count", 0),
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.post("/{community_id}/posts/{post_id}/like", response_model=CommunityPostResponse)
async def toggle_community_post_like(
    community_id: str,
    post_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_member(pool, community_id, user_id)

    try:
        post = await pool.fetchrow("SELECT id FROM community_posts WHERE id = $1 AND community_id = $2", post_id, community_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid post ID format")

    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")

    existing_like = await pool.fetchrow(
        "SELECT id FROM community_post_likes WHERE post_id = $1 AND user_id = $2",
        post_id, user_id
    )

    if existing_like:
        await pool.execute("DELETE FROM community_post_likes WHERE post_id = $1 AND user_id = $2", post_id, user_id)
        await pool.execute("UPDATE community_posts SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = $1", post_id)
    else:
        await pool.execute("INSERT INTO community_post_likes (post_id, user_id) VALUES ($1, $2)", post_id, user_id)
        await pool.execute("UPDATE community_posts SET likes_count = likes_count + 1 WHERE id = $1", post_id)

    row = await pool.fetchrow(
        """SELECT cp.*, u.name AS user_name, u.profile_image_url AS user_profile_image,
                  (SELECT COUNT(*) FROM community_post_comments WHERE post_id = cp.id) AS comments_count
           FROM community_posts cp
           JOIN users u ON cp.user_id = u.id
           WHERE cp.id = $1""",
        post_id
    )

    return CommunityPostResponse(
        id=str(row["id"]),
        community_id=str(row["community_id"]),
        user_id=str(row["user_id"]),
        user_name=row["user_name"],
        user_profile_image=row.get("user_profile_image"),
        image_url=row["image_url"],
        caption=row["caption"],
        likes_count=row["likes_count"],
        is_liked=existing_like is None,
        comments_count=row.get("comments_count", 0),
        created_at=row["created_at"],
    )


@router.post("/{community_id}/posts/{post_id}/comment", response_model=CommunityPostCommentResponse, status_code=status.HTTP_201_CREATED)
async def add_community_post_comment(
    community_id: str,
    post_id: str,
    data: CommunityPostCommentCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_member(pool, community_id, user_id)

    try:
        post = await pool.fetchrow("SELECT id FROM community_posts WHERE id = $1 AND community_id = $2", post_id, community_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid post ID format")

    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")

    row = await pool.fetchrow(
        "INSERT INTO community_post_comments (post_id, user_id, text) VALUES ($1, $2, $3) RETURNING *",
        post_id, user_id, data.text
    )

    return CommunityPostCommentResponse(
        id=str(row["id"]),
        post_id=str(row["post_id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        text=row["text"],
        created_at=row["created_at"],
    )


@router.get("/{community_id}/posts/{post_id}/comments", response_model=List[CommunityPostCommentResponse])
async def get_community_post_comments(
    community_id: str,
    post_id: str,
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    rows = await pool.fetch(
        """SELECT cpc.*, u.name AS user_name
           FROM community_post_comments cpc
           JOIN users u ON cpc.user_id = u.id
           WHERE cpc.post_id = $1
           ORDER BY cpc.created_at DESC
           OFFSET $2 LIMIT $3""",
        post_id, skip, limit
    )

    return [
        CommunityPostCommentResponse(
            id=str(row["id"]),
            post_id=str(row["post_id"]),
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            text=row["text"],
            created_at=row["created_at"],
        )
        for row in rows
    ]


# ── Community Group Chat ─────────────────────────────────────────────────────

@router.post("/{community_id}/messages", response_model=CommunityMessageResponse, status_code=status.HTTP_201_CREATED)
async def send_community_message(
    community_id: str,
    data: CommunityMessageCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_member(pool, community_id, user_id)

    # Check if admin-only chat is enabled for this community
    community_row = await pool.fetchrow("SELECT admin_only_chat FROM communities WHERE id = $1", community_id)
    if community_row and community_row.get("admin_only_chat"):
        member = await pool.fetchrow(
            "SELECT role FROM community_members WHERE community_id = $1 AND user_id = $2 AND status = 'active'",
            community_id, user_id
        )
        if not member or member["role"] != "admin":
            raise HTTPException(status_code=403, detail="Only admins can send messages in this chat")

    row = await pool.fetchrow(
        "INSERT INTO community_messages (community_id, user_id, message, image_url, message_type) VALUES ($1, $2, $3, $4, $5) RETURNING *",
        community_id, user_id, data.message, data.image_url, data.message_type
    )

    response = CommunityMessageResponse(
        id=str(row["id"]),
        community_id=str(row["community_id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        user_profile_image=current_user.get("profile_image_url"),
        message=row["message"],
        timestamp=row["timestamp"],
        image_url=row.get("image_url") or "",
        message_type=row.get("message_type") or "text",
    )

    # WebSocket fan-out to all community members
    try:
        member_rows = await pool.fetch(
            "SELECT user_id::text FROM community_members WHERE community_id = $1 AND status = 'active'",
            community_id
        )
        member_ids = [r["user_id"] for r in member_rows]
        ws_payload = {
            "type": "group_message",
            "channel": f"community:{community_id}",
            "id": response.id,
            "community_id": response.community_id,
            "user_id": response.user_id,
            "user_name": response.user_name or "",
            "user_profile_image": response.user_profile_image or "",
            "message": response.message,
            "timestamp": response.timestamp.isoformat(),
            "image_url": response.image_url,
            "message_type": response.message_type,
        }
        await ws_manager.broadcast_to_group(member_ids, ws_payload, exclude_user_id=user_id)
    except Exception:
        pass  # Don't fail the API call if broadcast fails

    return response


@router.get("/{community_id}/messages", response_model=List[CommunityMessageResponse])
async def get_community_messages(
    community_id: str,
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    rows = await pool.fetch(
        """SELECT cm.*, u.name AS user_name, u.profile_image_url AS user_profile_image
           FROM community_messages cm
           JOIN users u ON cm.user_id = u.id
           WHERE cm.community_id = $1
           ORDER BY cm.timestamp ASC
           OFFSET $2 LIMIT $3""",
        community_id, skip, limit
    )

    return [
        CommunityMessageResponse(
            id=str(row["id"]),
            community_id=str(row["community_id"]),
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            user_profile_image=row.get("user_profile_image"),
            message=row["message"],
            timestamp=row["timestamp"],
            image_url=row.get("image_url") or "",
            message_type=row.get("message_type") or "text",
            is_deleted=row.get("is_deleted") or False,
            deleted_by=str(row["deleted_by"]) if row.get("deleted_by") else None,
            is_pinned=row.get("is_pinned") or False,
        )
        for row in rows
    ]


@router.put("/{community_id}/messages/{message_id}")
async def edit_community_message(
    community_id: str,
    message_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Edit own community message."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    body = await request.json()
    new_text = body.get("message", "").strip()
    if not new_text:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Message text cannot be empty")

    msg = await pool.fetchrow(
        "SELECT * FROM community_messages WHERE id = $1 AND community_id = $2 AND user_id = $3",
        message_id, community_id, user_id,
    )
    if not msg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found or not yours")

    await pool.execute(
        "UPDATE community_messages SET message = $1 WHERE id = $2",
        new_text, message_id,
    )
    return {"status": "ok", "message": new_text}


@router.delete("/{community_id}/messages/{message_id}")
async def delete_community_message(
    community_id: str,
    message_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Delete community message for everyone (admin or message owner)."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    msg = await pool.fetchrow(
        "SELECT * FROM community_messages WHERE id = $1 AND community_id = $2",
        message_id, community_id,
    )
    if not msg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")

    # Check if admin or message owner
    is_admin = False
    admin_check = await pool.fetchrow(
        "SELECT role FROM community_members WHERE community_id = $1 AND user_id = $2 AND status = 'active'",
        community_id, user_id
    )
    if admin_check and admin_check["role"] == "admin":
        is_admin = True

    if str(msg["user_id"]) != user_id and not is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")

    # Soft delete
    await pool.execute(
        "UPDATE community_messages SET is_deleted = true, deleted_by = $1, message = 'This message was deleted' WHERE id = $2",
        user_id, message_id
    )
    return {"detail": "Message deleted", "deleted_by": current_user["name"]}


@router.post("/{community_id}/messages/{message_id}/pin")
async def pin_community_message(
    community_id: str,
    message_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Pin/unpin a community message (admin only)."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    msg = await pool.fetchrow(
        "SELECT id, is_pinned FROM community_messages WHERE id = $1 AND community_id = $2",
        message_id, community_id,
    )
    if not msg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")

    new_pinned = not (msg.get("is_pinned") or False)
    await pool.execute(
        "UPDATE community_messages SET is_pinned = $1 WHERE id = $2",
        new_pinned, message_id
    )
    return {"detail": "Message pinned" if new_pinned else "Message unpinned", "is_pinned": new_pinned}


# ── Sub-groups ───────────────────────────────────────────────────────────────

@router.post("/{community_id}/groups", response_model=SubGroupResponse, status_code=status.HTTP_201_CREATED)
async def create_sub_group(
    community_id: str,
    data: SubGroupCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    row = await pool.fetchrow(
        """INSERT INTO sub_groups (community_id, name, description, type, created_by)
           VALUES ($1, $2, $3, $4, $5) RETURNING *""",
        community_id, data.name, data.description, data.type, user_id
    )

    group_id = str(row["id"])

    # Add creator as member
    await pool.execute(
        "INSERT INTO sub_group_members (sub_group_id, user_id) VALUES ($1, $2)",
        group_id, user_id
    )

    return SubGroupResponse(
        id=group_id,
        community_id=str(row["community_id"]),
        name=row["name"],
        description=row["description"],
        type=row["type"],
        is_private=row.get("is_private", False) or False,
        admin_only_chat=row.get("admin_only_chat", False) or False,
        created_by=str(row["created_by"]),
        creator_name=current_user["name"],
        members_count=1,
        is_member=True,
        created_at=row["created_at"],
    )


@router.get("/{community_id}/groups", response_model=List[SubGroupResponse])
async def list_sub_groups(
    community_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """SELECT sg.*, u.name AS creator_name,
                  (SELECT COUNT(*) FROM sub_group_members WHERE sub_group_id = sg.id AND status = 'active') AS members_count,
                  EXISTS(SELECT 1 FROM sub_group_members WHERE sub_group_id = sg.id AND user_id = $2 AND status = 'active') AS is_member,
                  (SELECT status FROM sub_group_members WHERE sub_group_id = sg.id AND user_id = $2 LIMIT 1) AS member_status
           FROM sub_groups sg
           JOIN users u ON sg.created_by = u.id
           WHERE sg.community_id = $1
           ORDER BY sg.created_at ASC""",
        community_id, user_id
    )

    return [
        SubGroupResponse(
            id=str(row["id"]),
            community_id=str(row["community_id"]),
            name=row["name"],
            description=row["description"],
            type=row["type"],
            is_private=row.get("is_private", False) or False,
            admin_only_chat=row.get("admin_only_chat", False) or False,
            created_by=str(row["created_by"]),
            creator_name=row["creator_name"],
            members_count=row["members_count"],
            is_member=row["is_member"],
            member_status=row.get("member_status"),
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.put("/{community_id}/groups/{group_id}", response_model=SubGroupResponse)
async def update_sub_group(
    community_id: str,
    group_id: str,
    data: SubGroupCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    row = await pool.fetchrow(
        """UPDATE sub_groups SET name = $1, description = $2, type = $3
           WHERE id = $4 AND community_id = $5 RETURNING *""",
        data.name, data.description, data.type, group_id, community_id
    )

    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sub-group not found")

    members_count = await pool.fetchval(
        "SELECT COUNT(*) FROM sub_group_members WHERE sub_group_id = $1", group_id
    )

    creator = await pool.fetchrow("SELECT name FROM users WHERE id = $1", str(row["created_by"]))

    return SubGroupResponse(
        id=str(row["id"]),
        community_id=str(row["community_id"]),
        name=row["name"],
        description=row["description"],
        type=row["type"],
        is_private=row.get("is_private", False) or False,
        admin_only_chat=row.get("admin_only_chat", False) or False,
        created_by=str(row["created_by"]),
        creator_name=creator["name"] if creator else None,
        members_count=members_count or 0,
        is_member=True,
        created_at=row["created_at"],
    )


@router.delete("/{community_id}/groups/{group_id}", status_code=status.HTTP_200_OK)
async def delete_sub_group(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    result = await pool.execute(
        "DELETE FROM sub_groups WHERE id = $1 AND community_id = $2",
        group_id, community_id
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sub-group not found")

    return {"detail": "Sub-group deleted successfully"}


@router.post("/{community_id}/groups/{group_id}/join", status_code=status.HTTP_200_OK)
async def join_sub_group(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_member(pool, community_id, user_id)

    try:
        group = await pool.fetchrow(
            "SELECT id, is_private FROM sub_groups WHERE id = $1 AND community_id = $2",
            group_id, community_id
        )
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid group ID format")

    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sub-group not found")

    is_private = group.get("is_private", False)

    # Check if already a member or has a pending request
    existing = await pool.fetchrow(
        "SELECT id, status FROM sub_group_members WHERE sub_group_id = $1 AND user_id = $2",
        group_id, user_id
    )
    if existing:
        if existing["status"] == "active":
            return {"detail": "Already a member"}
        elif existing["status"] == "pending":
            return {"detail": "Join request already pending", "status": "pending"}
        # If rejected, allow re-request by updating status
        member_status = "pending" if is_private else "active"
        await pool.execute(
            "UPDATE sub_group_members SET status = $1 WHERE sub_group_id = $2 AND user_id = $3",
            member_status, group_id, user_id
        )
        if member_status == "pending":
            return {"detail": "Join request sent", "status": "pending"}
        return {"detail": "Joined sub-group"}

    member_status = "pending" if is_private else "active"

    await pool.execute(
        "INSERT INTO sub_group_members (sub_group_id, user_id, status) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
        group_id, user_id, member_status
    )

    if member_status == "pending":
        return {"detail": "Join request sent", "status": "pending"}

    return {"detail": "Joined sub-group"}


@router.post("/{community_id}/groups/{group_id}/request-join", status_code=status.HTTP_200_OK)
async def request_join_sub_group(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Must be community member first
    community_member = await _get_membership(pool, community_id, user_id)
    if not community_member:
        raise HTTPException(status_code=403, detail="Join the community first")

    existing = await pool.fetchrow(
        "SELECT id, status FROM sub_group_members WHERE sub_group_id = $1 AND user_id = $2",
        group_id, user_id
    )
    if existing:
        if existing["status"] == "pending":
            return {"detail": "Request already pending"}
        return {"detail": "Already a member"}

    await pool.execute(
        "INSERT INTO sub_group_members (sub_group_id, user_id, status) VALUES ($1, $2, 'pending')",
        group_id, user_id
    )
    return {"detail": "Join request sent"}


@router.post("/{community_id}/groups/{group_id}/leave", status_code=status.HTTP_200_OK)
async def leave_sub_group(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await pool.execute(
        "DELETE FROM sub_group_members WHERE sub_group_id = $1 AND user_id = $2",
        group_id, user_id
    )

    return {"detail": "Left sub-group"}


# ── Sub-group Members ───────────────────────────────────────────────────────

@router.get("/{community_id}/groups/{group_id}/members", response_model=List[SubGroupMemberResponse])
async def list_sub_group_members(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    # Verify the sub-group belongs to the community
    try:
        group = await pool.fetchrow(
            "SELECT id FROM sub_groups WHERE id = $1 AND community_id = $2",
            group_id, community_id
        )
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid ID format")

    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sub-group not found")

    rows = await pool.fetch(
        """SELECT sgm.id, sgm.user_id, sgm.joined_at,
                  u.name AS user_name, u.profile_image_url AS user_profile_image
           FROM sub_group_members sgm
           JOIN users u ON sgm.user_id = u.id
           WHERE sgm.sub_group_id = $1
           ORDER BY sgm.joined_at ASC""",
        group_id
    )

    return [
        SubGroupMemberResponse(
            id=str(row["id"]),
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            user_profile_image=row.get("user_profile_image"),
            joined_at=row["joined_at"],
        )
        for row in rows
    ]


# ── Sub-group Messages ──────────────────────────────────────────────────────

@router.post("/{community_id}/groups/{group_id}/messages", response_model=SubGroupMessageResponse, status_code=status.HTTP_201_CREATED)
async def send_sub_group_message(
    community_id: str,
    group_id: str,
    data: SubGroupMessageCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Check membership
    member = await pool.fetchrow(
        "SELECT id, status FROM sub_group_members WHERE sub_group_id = $1 AND user_id = $2",
        group_id, user_id
    )

    if not member:
        # Check if group is private
        group = await pool.fetchrow("SELECT is_private FROM sub_groups WHERE id = $1", group_id)
        if group and group.get("is_private"):
            raise HTTPException(status_code=403, detail="This is a private group. Request to join first.")

        # Public group — must be community member first
        community_member = await _get_membership(pool, community_id, user_id)
        if not community_member:
            raise HTTPException(status_code=403, detail="Join the community first before chatting in groups.")

        # Auto-join public sub-group
        try:
            await pool.execute(
                "INSERT INTO sub_group_members (sub_group_id, user_id, status) VALUES ($1, $2, 'active')",
                group_id, user_id
            )
        except Exception:
            pass
    elif member.get("status") == "pending":
        raise HTTPException(status_code=403, detail="Your join request is pending admin approval.")

    # Check if admin-only chat is enabled for this sub-group
    group_row = await pool.fetchrow("SELECT admin_only_chat FROM sub_groups WHERE id = $1", group_id)
    if group_row and group_row.get("admin_only_chat"):
        cm = await pool.fetchrow(
            "SELECT role FROM community_members WHERE community_id = $1 AND user_id = $2 AND status = 'active'",
            community_id, user_id
        )
        if not cm or cm["role"] != "admin":
            raise HTTPException(status_code=403, detail="Only admins can send messages in this group")

    row = await pool.fetchrow(
        "INSERT INTO sub_group_messages (sub_group_id, user_id, message, image_url, message_type) VALUES ($1, $2, $3, $4, $5) RETURNING *",
        group_id, user_id, data.message, data.image_url, data.message_type
    )

    response = SubGroupMessageResponse(
        id=str(row["id"]),
        sub_group_id=str(row["sub_group_id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        user_profile_image=current_user.get("profile_image_url"),
        message=row["message"],
        timestamp=row["timestamp"],
        image_url=row.get("image_url") or "",
        message_type=row.get("message_type") or "text",
    )

    # WebSocket fan-out to all sub-group members
    try:
        member_rows = await pool.fetch(
            "SELECT user_id::text FROM sub_group_members WHERE sub_group_id = $1 AND status = 'active'",
            group_id
        )
        member_ids = [r["user_id"] for r in member_rows]
        ws_payload = {
            "type": "group_message",
            "channel": f"subgroup:{group_id}",
            "id": response.id,
            "sub_group_id": response.sub_group_id,
            "community_id": community_id,
            "user_id": response.user_id,
            "user_name": response.user_name or "",
            "user_profile_image": response.user_profile_image or "",
            "message": response.message,
            "timestamp": response.timestamp.isoformat(),
            "image_url": response.image_url,
            "message_type": response.message_type,
        }
        await ws_manager.broadcast_to_group(member_ids, ws_payload, exclude_user_id=user_id)
    except Exception:
        pass

    return response


@router.get("/{community_id}/groups/{group_id}/messages", response_model=List[SubGroupMessageResponse])
async def get_sub_group_messages(
    community_id: str,
    group_id: str,
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    rows = await pool.fetch(
        """SELECT sgm.*, u.name AS user_name, u.profile_image_url AS user_profile_image
           FROM sub_group_messages sgm
           JOIN users u ON sgm.user_id = u.id
           WHERE sgm.sub_group_id = $1
           ORDER BY sgm.timestamp ASC
           OFFSET $2 LIMIT $3""",
        group_id, skip, limit
    )

    return [
        SubGroupMessageResponse(
            id=str(row["id"]),
            sub_group_id=str(row["sub_group_id"]),
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            user_profile_image=row.get("user_profile_image"),
            message=row["message"],
            timestamp=row["timestamp"],
            image_url=row.get("image_url") or "",
            message_type=row.get("message_type") or "text",
            is_deleted=row.get("is_deleted") or False,
            deleted_by=str(row["deleted_by"]) if row.get("deleted_by") else None,
            is_pinned=row.get("is_pinned") or False,
        )
        for row in rows
    ]


@router.put("/{community_id}/groups/{group_id}/messages/{message_id}")
async def edit_sub_group_message(
    community_id: str,
    group_id: str,
    message_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Edit own sub-group message."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    body = await request.json()
    new_text = body.get("message", "").strip()
    if not new_text:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Message text cannot be empty")

    msg = await pool.fetchrow(
        "SELECT * FROM sub_group_messages WHERE id = $1 AND sub_group_id = $2 AND user_id = $3",
        message_id, group_id, user_id,
    )
    if not msg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found or not yours")

    await pool.execute(
        "UPDATE sub_group_messages SET message = $1 WHERE id = $2",
        new_text, message_id,
    )
    return {"status": "ok", "message": new_text}


@router.delete("/{community_id}/groups/{group_id}/messages/{message_id}")
async def delete_sub_group_message(
    community_id: str,
    group_id: str,
    message_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Delete sub-group message for everyone (admin or message owner)."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    msg = await pool.fetchrow(
        "SELECT * FROM sub_group_messages WHERE id = $1 AND sub_group_id = $2",
        message_id, group_id,
    )
    if not msg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")

    # Check if admin or message owner
    is_admin = False
    admin_check = await pool.fetchrow(
        "SELECT role FROM community_members WHERE community_id = $1 AND user_id = $2 AND status = 'active'",
        community_id, user_id
    )
    if admin_check and admin_check["role"] == "admin":
        is_admin = True

    if str(msg["user_id"]) != user_id and not is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized")

    # Soft delete
    await pool.execute(
        "UPDATE sub_group_messages SET is_deleted = true, deleted_by = $1, message = 'This message was deleted' WHERE id = $2",
        user_id, message_id
    )
    return {"detail": "Message deleted", "deleted_by": current_user["name"]}


@router.post("/{community_id}/groups/{group_id}/messages/{message_id}/pin")
async def pin_sub_group_message(
    community_id: str,
    group_id: str,
    message_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Pin/unpin a sub-group message (admin only)."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    msg = await pool.fetchrow(
        "SELECT id, is_pinned FROM sub_group_messages WHERE id = $1 AND sub_group_id = $2",
        message_id, group_id,
    )
    if not msg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")

    new_pinned = not (msg.get("is_pinned") or False)
    await pool.execute(
        "UPDATE sub_group_messages SET is_pinned = $1 WHERE id = $2",
        new_pinned, message_id
    )
    return {"detail": "Message pinned" if new_pinned else "Message unpinned", "is_pinned": new_pinned}


@router.get("/{community_id}/groups/{group_id}/messages/pinned")
async def get_pinned_sub_group_messages(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Get all pinned messages in a sub-group."""
    pool = request.app.state.pool

    rows = await pool.fetch(
        """SELECT sgm.*, u.name AS user_name, u.profile_image_url AS user_profile_image
           FROM sub_group_messages sgm
           JOIN users u ON sgm.user_id = u.id
           WHERE sgm.sub_group_id = $1 AND sgm.is_pinned = true
           ORDER BY sgm.timestamp DESC""",
        group_id
    )

    return [
        {
            "id": str(row["id"]),
            "sub_group_id": str(row["sub_group_id"]),
            "user_id": str(row["user_id"]),
            "user_name": row["user_name"],
            "user_profile_image": row.get("user_profile_image"),
            "message": row["message"],
            "timestamp": row["timestamp"].isoformat() if row["timestamp"] else None,
            "image_url": row.get("image_url") or "",
            "message_type": row.get("message_type") or "text",
            "is_pinned": True,
        }
        for row in rows
    ]


@router.post("/{community_id}/groups/{group_id}/polls")
async def create_poll(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Create a poll in a sub-group chat."""
    import json as json_lib
    pool = request.app.state.pool
    user_id = current_user["id"]

    body = await request.json()
    question = body.get("question", "").strip()
    options = body.get("options", [])
    is_anonymous = body.get("is_anonymous", False)
    is_multiple_choice = body.get("is_multiple_choice", False)

    if not question:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Question is required")
    if len(options) < 2:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="At least 2 options are required")

    options_json = json_lib.dumps([{"text": o, "votes": 0} for o in options])

    row = await pool.fetchrow(
        """INSERT INTO chat_polls (sub_group_id, created_by, question, options, is_anonymous, is_multiple_choice)
           VALUES ($1, $2, $3, $4, $5, $6) RETURNING *""",
        group_id, user_id, question, options_json, is_anonymous, is_multiple_choice
    )

    poll_id = str(row["id"])

    # Also insert a message of type 'poll' referencing this poll
    await pool.execute(
        "INSERT INTO sub_group_messages (sub_group_id, user_id, message, message_type, image_url) VALUES ($1, $2, $3, 'poll', $4)",
        group_id, user_id, question, poll_id
    )

    return {
        "id": poll_id,
        "question": question,
        "options": [{"text": o, "votes": 0} for o in options],
        "is_anonymous": is_anonymous,
        "is_multiple_choice": is_multiple_choice,
        "created_by": user_id,
        "created_at": row["created_at"].isoformat() if row["created_at"] else None,
    }


@router.post("/{community_id}/groups/{group_id}/polls/{poll_id}/vote")
async def vote_on_poll(
    community_id: str,
    group_id: str,
    poll_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Vote on a poll option (toggle)."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    body = await request.json()
    option_index = body.get("option_index")

    if option_index is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="option_index is required")

    poll = await pool.fetchrow("SELECT * FROM chat_polls WHERE id = $1", poll_id)
    if not poll:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Poll not found")

    is_multiple_choice = poll.get("is_multiple_choice", False)

    # Check if already voted on this option
    existing = await pool.fetchrow(
        "SELECT id FROM chat_poll_votes WHERE poll_id = $1 AND user_id = $2 AND option_index = $3",
        poll_id, user_id, option_index
    )

    if existing:
        # Remove vote (toggle)
        await pool.execute("DELETE FROM chat_poll_votes WHERE id = $1", str(existing["id"]))
    else:
        if not is_multiple_choice:
            # Remove previous votes for single-choice
            await pool.execute("DELETE FROM chat_poll_votes WHERE poll_id = $1 AND user_id = $2", poll_id, user_id)
        await pool.execute(
            "INSERT INTO chat_poll_votes (poll_id, user_id, option_index) VALUES ($1, $2, $3)",
            poll_id, user_id, option_index
        )

    # Return updated poll with vote counts
    import json as json_lib
    options = json_lib.loads(poll["options"]) if isinstance(poll["options"], str) else poll["options"]
    vote_rows = await pool.fetch(
        "SELECT option_index, COUNT(*) AS cnt FROM chat_poll_votes WHERE poll_id = $1 GROUP BY option_index",
        poll_id
    )
    vote_map = {r["option_index"]: r["cnt"] for r in vote_rows}

    user_votes = await pool.fetch(
        "SELECT option_index FROM chat_poll_votes WHERE poll_id = $1 AND user_id = $2",
        poll_id, user_id
    )
    user_voted = [r["option_index"] for r in user_votes]

    total_votes = sum(vote_map.values())
    updated_options = []
    for i, opt in enumerate(options):
        updated_options.append({
            "text": opt["text"],
            "votes": vote_map.get(i, 0),
        })

    return {
        "id": str(poll["id"]),
        "question": poll["question"],
        "options": updated_options,
        "total_votes": total_votes,
        "user_votes": user_voted,
        "is_anonymous": poll.get("is_anonymous", False),
        "is_multiple_choice": is_multiple_choice,
    }


@router.get("/{community_id}/groups/{group_id}/polls/{poll_id}")
async def get_poll(
    community_id: str,
    group_id: str,
    poll_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Get poll details with vote counts."""
    import json as json_lib
    pool = request.app.state.pool
    user_id = current_user["id"]

    poll = await pool.fetchrow("SELECT * FROM chat_polls WHERE id = $1", poll_id)
    if not poll:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Poll not found")

    options = json_lib.loads(poll["options"]) if isinstance(poll["options"], str) else poll["options"]
    vote_rows = await pool.fetch(
        "SELECT option_index, COUNT(*) AS cnt FROM chat_poll_votes WHERE poll_id = $1 GROUP BY option_index",
        poll_id
    )
    vote_map = {r["option_index"]: r["cnt"] for r in vote_rows}

    user_votes = await pool.fetch(
        "SELECT option_index FROM chat_poll_votes WHERE poll_id = $1 AND user_id = $2",
        poll_id, user_id
    )
    user_voted = [r["option_index"] for r in user_votes]

    total_votes = sum(vote_map.values())
    updated_options = []
    for i, opt in enumerate(options):
        updated_options.append({
            "text": opt["text"],
            "votes": vote_map.get(i, 0),
        })

    return {
        "id": str(poll["id"]),
        "question": poll["question"],
        "options": updated_options,
        "total_votes": total_votes,
        "user_votes": user_voted,
        "is_anonymous": poll.get("is_anonymous", False),
        "is_multiple_choice": poll.get("is_multiple_choice", False),
        "created_by": str(poll["created_by"]),
        "created_at": poll["created_at"].isoformat() if poll["created_at"] else None,
    }


@router.post("/{community_id}/groups/{group_id}/messages/location")
async def share_location(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Share a location message in a sub-group chat."""
    import json as json_lib
    pool = request.app.state.pool
    user_id = current_user["id"]

    body = await request.json()
    lat = body.get("latitude")
    lng = body.get("longitude")
    address = body.get("address", "")

    if lat is None or lng is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="latitude and longitude are required")

    location_data = json_lib.dumps({"lat": lat, "lng": lng, "address": address})

    row = await pool.fetchrow(
        "INSERT INTO sub_group_messages (sub_group_id, user_id, message, message_type, image_url) VALUES ($1, $2, $3, 'location', $4) RETURNING *",
        group_id, user_id, address or "Shared location", location_data
    )

    return {
        "id": str(row["id"]),
        "sub_group_id": str(row["sub_group_id"]),
        "user_id": str(row["user_id"]),
        "user_name": current_user["name"],
        "user_profile_image": current_user.get("profile_image_url"),
        "message": row["message"],
        "timestamp": row["timestamp"].isoformat() if row["timestamp"] else None,
        "image_url": row.get("image_url") or "",
        "message_type": "location",
    }


# ── Helper: build event response with trip fields ────────────────────────────

def _event_row_to_response(row, creator_name=None, is_booked=False, participants_count=0):
    from datetime import datetime as dt
    event_date = row["date"]
    is_past = event_date < dt.utcnow() if event_date else False

    return CommunityEventResponse(
        id=str(row["id"]),
        community_id=str(row["community_id"]),
        title=row["title"],
        description=row["description"],
        location=row["location"],
        date=row["date"],
        price=row["price"],
        slots=row["slots"],
        image_url=row["image_url"],
        created_by=str(row["created_by"]),
        creator_name=creator_name,
        is_booked=is_booked,
        is_joined=is_booked,
        participants_count=participants_count,
        event_type=row.get("event_type", "event") or "event",
        duration_days=row.get("duration_days", 1) or 1,
        difficulty=row.get("difficulty", "easy") or "easy",
        includes=list(row.get("includes") or []),
        excludes=list(row.get("excludes") or []),
        meeting_point=row.get("meeting_point", "") or "",
        end_date=row.get("end_date"),
        max_altitude_m=row.get("max_altitude_m", 0) or 0,
        total_distance_km=row.get("total_distance_km", 0) or 0,
        community_name=row.get("community_name"),
        community_image=row.get("community_image"),
        is_past=is_past,
        venue_lat=float(row.get("venue_lat") or 0),
        venue_lng=float(row.get("venue_lng") or 0),
        created_at=row["created_at"],
    )


# ── Nearby cities map (Indian cities within ~500km radius) ────────────────────

NEARBY_CITIES = {
    "chennai": ["chennai", "bangalore", "bengaluru", "pondicherry", "vellore", "coimbatore", "madurai", "mysore", "mysuru", "tirupati", "hyderabad"],
    "bangalore": ["bangalore", "bengaluru", "mysore", "mysuru", "chennai", "coimbatore", "mangalore", "mangaluru", "hyderabad", "ooty", "kodaikanal"],
    "bengaluru": ["bangalore", "bengaluru", "mysore", "mysuru", "chennai", "coimbatore", "mangalore", "mangaluru", "hyderabad", "ooty", "kodaikanal"],
    "mumbai": ["mumbai", "pune", "lonavala", "nashik", "goa", "alibaug", "mahabaleshwar", "lavasa", "kolhapur", "aurangabad"],
    "pune": ["pune", "mumbai", "lonavala", "mahabaleshwar", "lavasa", "nashik", "kolhapur", "goa", "alibaug"],
    "delhi": ["delhi", "new delhi", "gurgaon", "gurugram", "noida", "agra", "jaipur", "chandigarh", "manali", "shimla", "rishikesh", "dehradun", "haridwar", "mussoorie"],
    "new delhi": ["delhi", "new delhi", "gurgaon", "gurugram", "noida", "agra", "jaipur", "chandigarh", "manali", "shimla", "rishikesh", "dehradun"],
    "hyderabad": ["hyderabad", "bangalore", "bengaluru", "chennai", "warangal", "vijayawada", "tirupati"],
    "kolkata": ["kolkata", "darjeeling", "siliguri", "gangtok", "puri", "bhubaneswar"],
    "goa": ["goa", "mumbai", "pune", "mangalore", "mangaluru", "belgaum"],
    "jaipur": ["jaipur", "delhi", "udaipur", "jodhpur", "pushkar", "ajmer", "mount abu"],
    "ahmedabad": ["ahmedabad", "gandhinagar", "vadodara", "surat", "rajkot", "mount abu", "udaipur"],
    "chandigarh": ["chandigarh", "delhi", "shimla", "manali", "amritsar", "dharamshala", "mcleodganj"],
    "manali": ["manali", "shimla", "dharamshala", "mcleodganj", "kullu", "delhi", "chandigarh", "leh", "ladakh"],
    "shimla": ["shimla", "manali", "chandigarh", "delhi", "dharamshala", "mcleodganj", "kasauli"],
    "kochi": ["kochi", "cochin", "munnar", "alleppey", "alappuzha", "trivandrum", "thiruvananthapuram", "thekkady", "wayanad"],
}


def _get_nearby_cities(city: str) -> list:
    """Get list of nearby cities for a given city."""
    city_lower = city.lower().strip()
    return NEARBY_CITIES.get(city_lower, [city_lower])


# ── Global Explore: All trips & events ────────────────────────────────────────

@router.get("/explore/all-events", response_model=List[CommunityEventResponse])
async def explore_all_events(
    request: Request,
    event_type: str = Query("all"),       # "all", "trip", "event"
    location: str = Query(""),
    difficulty: str = Query(""),
    include_past: bool = Query(False),    # only show future events by default
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    """Return all events/trips across all communities for the explore page.
    When location is provided, shows events from nearby cities too, sorted by proximity."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    where_parts = []
    params = []
    idx = 1

    # Hide past events by default
    if not include_past:
        where_parts.append("(ce.date >= NOW() OR ce.end_date >= NOW())")

    if event_type and event_type != "all":
        where_parts.append(f"ce.event_type = ${idx}")
        params.append(event_type)
        idx += 1

    # Location: search in nearby cities, not just exact match
    nearby_cities = []
    if location:
        nearby_cities = _get_nearby_cities(location)
        # Build OR conditions for each nearby city
        city_conditions = []
        for city in nearby_cities:
            city_conditions.append(f"LOWER(ce.location) LIKE LOWER(${idx})")
            params.append(f"%{city}%")
            idx += 1
        where_parts.append(f"({' OR '.join(city_conditions)})")

    if difficulty and difficulty != "all":
        where_parts.append(f"ce.difficulty = ${idx}")
        params.append(difficulty)
        idx += 1

    where_clause = "WHERE " + " AND ".join(where_parts) if where_parts else ""

    # Sort: if location provided, prioritize exact city match first
    order_clause = "ORDER BY ce.date ASC"
    if location and nearby_cities:
        # Events in the exact city come first, then nearby
        primary_city = nearby_cities[0]
        order_clause = f"""ORDER BY
            CASE WHEN LOWER(ce.location) LIKE LOWER('%{primary_city}%') THEN 0 ELSE 1 END,
            ce.date ASC"""

    params.append(skip)
    skip_idx = idx
    idx += 1
    params.append(limit)
    limit_idx = idx

    rows = await pool.fetch(
        f"""SELECT ce.*, u.name AS creator_name,
                   c.name AS community_name, c.image_url AS community_image,
                   EXISTS(SELECT 1 FROM community_event_bookings WHERE event_id = ce.id AND user_id = '{user_id}') AS is_booked,
                   (SELECT COUNT(*) FROM community_event_bookings WHERE event_id = ce.id) AS participants_count
            FROM community_events ce
            JOIN users u ON ce.created_by = u.id
            JOIN communities c ON ce.community_id = c.id
            {where_clause}
            {order_clause}
            OFFSET ${skip_idx} LIMIT ${limit_idx}""",
        *params
    )

    results = []
    for row in rows:
        resp = _event_row_to_response(row, creator_name=row["creator_name"], is_booked=row["is_booked"], participants_count=row["participants_count"])
        results.append(resp)
    return results


# ── Community Events ─────────────────────────────────────────────────────────

@router.post("/{community_id}/events", response_model=CommunityEventResponse, status_code=status.HTTP_201_CREATED)
async def create_community_event(
    community_id: str,
    data: CommunityEventCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_member(pool, community_id, user_id)

    # Strip timezone info — DB column is timestamp without time zone
    event_date = data.date.replace(tzinfo=None)
    end_date = data.end_date.replace(tzinfo=None) if data.end_date else None

    row = await pool.fetchrow(
        """INSERT INTO community_events (community_id, title, description, location, date, price, slots, image_url, created_by,
           event_type, duration_days, difficulty, includes, excludes, meeting_point, end_date, max_altitude_m, total_distance_km,
           venue_lat, venue_lng)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20) RETURNING *""",
        community_id, data.title, data.description, data.location, event_date, data.price, data.slots, data.image_url, user_id,
        data.event_type, data.duration_days, data.difficulty, data.includes, data.excludes, data.meeting_point, end_date,
        data.max_altitude_m, data.total_distance_km, data.venue_lat, data.venue_lng
    )

    return _event_row_to_response(row, creator_name=current_user["name"], is_booked=False, participants_count=0)


@router.get("/{community_id}/events", response_model=List[CommunityEventResponse])
async def list_community_events(
    community_id: str,
    request: Request,
    include_past: bool = Query(False),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    date_filter = "" if include_past else "AND (ce.date >= NOW() OR ce.end_date >= NOW())"

    rows = await pool.fetch(
        f"""SELECT ce.*, u.name AS creator_name,
                  c.name AS community_name, c.image_url AS community_image,
                  EXISTS(SELECT 1 FROM community_event_bookings WHERE event_id = ce.id AND user_id = $2) AS is_booked,
                  (SELECT COUNT(*) FROM community_event_bookings WHERE event_id = ce.id) AS participants_count
           FROM community_events ce
           JOIN users u ON ce.created_by = u.id
           JOIN communities c ON ce.community_id = c.id
           WHERE ce.community_id = $1 {date_filter}
           ORDER BY ce.date ASC""",
        community_id, user_id
    )

    return [
        _event_row_to_response(row, creator_name=row["creator_name"], is_booked=row["is_booked"], participants_count=row["participants_count"])
        for row in rows
    ]


@router.get("/{community_id}/events/{event_id}", response_model=CommunityEventResponse)
async def get_community_event(
    community_id: str,
    event_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    row = await pool.fetchrow(
        """SELECT ce.*, u.name AS creator_name,
                  c.name AS community_name, c.image_url AS community_image,
                  EXISTS(SELECT 1 FROM community_event_bookings WHERE event_id = ce.id AND user_id = $2) AS is_booked,
                  (SELECT COUNT(*) FROM community_event_bookings WHERE event_id = ce.id) AS participants_count
           FROM community_events ce
           JOIN users u ON ce.created_by = u.id
           JOIN communities c ON ce.community_id = c.id
           WHERE ce.id = $1 AND ce.community_id = $3""",
        event_id, user_id, community_id
    )

    if not row:
        raise HTTPException(status_code=404, detail="Event not found")

    return _event_row_to_response(row, creator_name=row["creator_name"], is_booked=row["is_booked"], participants_count=row["participants_count"])


@router.put("/{community_id}/events/{event_id}", response_model=CommunityEventResponse)
async def update_community_event(
    community_id: str,
    event_id: str,
    data: CommunityEventCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    # Strip timezone info — DB column is timestamp without time zone
    event_date = data.date.replace(tzinfo=None)
    end_date = data.end_date.replace(tzinfo=None) if data.end_date else None

    row = await pool.fetchrow(
        """UPDATE community_events
           SET title=$1, description=$2, location=$3, date=$4, price=$5, slots=$6, image_url=$7,
               event_type=$8, duration_days=$9, difficulty=$10, includes=$11, excludes=$12,
               meeting_point=$13, end_date=$14, max_altitude_m=$15, total_distance_km=$16,
               venue_lat=$17, venue_lng=$18
           WHERE id = $19 AND community_id = $20 RETURNING *""",
        data.title, data.description, data.location, event_date, data.price, data.slots, data.image_url,
        data.event_type, data.duration_days, data.difficulty, data.includes, data.excludes,
        data.meeting_point, end_date, data.max_altitude_m, data.total_distance_km,
        data.venue_lat, data.venue_lng,
        event_id, community_id
    )

    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    creator = await pool.fetchrow("SELECT name FROM users WHERE id = $1", str(row["created_by"]))

    return _event_row_to_response(row, creator_name=creator["name"] if creator else None, is_booked=False, participants_count=0)


@router.delete("/{community_id}/events/{event_id}", status_code=status.HTTP_200_OK)
async def delete_community_event(
    community_id: str,
    event_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    result = await pool.execute(
        "DELETE FROM community_events WHERE id = $1 AND community_id = $2",
        event_id, community_id
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    return {"detail": "Event deleted successfully"}


@router.get("/{community_id}/events/{event_id}/participants", response_model=List[EventParticipantResponse])
async def get_event_participants(
    community_id: str,
    event_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    rows = await pool.fetch(
        """SELECT b.user_id, u.name AS user_name, u.profile_image_url AS user_profile_image, b.created_at AS booked_at
           FROM community_event_bookings b
           JOIN users u ON u.id = b.user_id
           WHERE b.event_id = $1
           ORDER BY b.created_at ASC""",
        event_id,
    )

    return [
        EventParticipantResponse(
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            user_profile_image=row["user_profile_image"],
            booked_at=row["booked_at"],
        )
        for row in rows
    ]


@router.post("/{community_id}/events/{event_id}/book", response_model=CommunityEventBookingResponse, status_code=status.HTTP_201_CREATED)
async def book_community_event(
    community_id: str,
    event_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Auto-join community if not a member
    member = await _get_membership(pool, community_id, user_id)
    if not member:
        try:
            await pool.execute(
                "INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1, $2, 'member', 'active')",
                community_id, user_id
            )
        except Exception:
            pass  # might already exist with different status

    try:
        event = await pool.fetchrow(
            "SELECT * FROM community_events WHERE id = $1 AND community_id = $2",
            event_id, community_id
        )
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid event ID format")

    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    existing = await pool.fetchrow(
        "SELECT id FROM community_event_bookings WHERE event_id = $1 AND user_id = $2",
        event_id, user_id
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Already booked")

    row = await pool.fetchrow(
        """INSERT INTO community_event_bookings (event_id, user_id, payment_status, amount)
           VALUES ($1, $2, 'confirmed', $3) RETURNING *""",
        event_id, user_id, event["price"]
    )

    return CommunityEventBookingResponse(
        id=str(row["id"]),
        event_id=str(row["event_id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        payment_status=row["payment_status"],
        payment_id=row["payment_id"],
        amount=row["amount"],
        created_at=row["created_at"],
    )


# ── Event Itinerary ──────────────────────────────────────────────────────────

@router.get("/{community_id}/events/{event_id}/itinerary", response_model=List[ItineraryDayResponse])
async def get_event_itinerary(
    community_id: str,
    event_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    rows = await pool.fetch(
        """SELECT * FROM event_itinerary
           WHERE event_id = $1
           ORDER BY day_number ASC""",
        event_id,
    )

    return [
        ItineraryDayResponse(
            id=str(row["id"]),
            event_id=str(row["event_id"]),
            day_number=row["day_number"],
            title=row["title"],
            description=row["description"],
            activities=list(row.get("activities") or []),
            meals_included=list(row.get("meals_included") or []),
            accommodation=row.get("accommodation", "") or "",
            distance_km=row.get("distance_km", 0) or 0,
            elevation_m=row.get("elevation_m", 0) or 0,
        )
        for row in rows
    ]


@router.post("/{community_id}/events/{event_id}/itinerary", response_model=ItineraryDayResponse, status_code=status.HTTP_201_CREATED)
async def add_itinerary_day(
    community_id: str,
    event_id: str,
    data: ItineraryDayCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    # Verify event exists
    event = await pool.fetchrow(
        "SELECT id FROM community_events WHERE id = $1 AND community_id = $2",
        event_id, community_id
    )
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    row = await pool.fetchrow(
        """INSERT INTO event_itinerary (event_id, day_number, title, description, activities, meals_included, accommodation, distance_km, elevation_m)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *""",
        event_id, data.day_number, data.title, data.description, data.activities,
        data.meals_included, data.accommodation, data.distance_km, data.elevation_m
    )

    return ItineraryDayResponse(
        id=str(row["id"]),
        event_id=str(row["event_id"]),
        day_number=row["day_number"],
        title=row["title"],
        description=row["description"],
        activities=list(row.get("activities") or []),
        meals_included=list(row.get("meals_included") or []),
        accommodation=row.get("accommodation", "") or "",
        distance_km=row.get("distance_km", 0) or 0,
        elevation_m=row.get("elevation_m", 0) or 0,
    )


@router.put("/{community_id}/events/{event_id}/itinerary/{day_id}", response_model=ItineraryDayResponse)
async def update_itinerary_day(
    community_id: str,
    event_id: str,
    day_id: str,
    data: ItineraryDayCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    row = await pool.fetchrow(
        """UPDATE event_itinerary
           SET day_number=$1, title=$2, description=$3, activities=$4, meals_included=$5,
               accommodation=$6, distance_km=$7, elevation_m=$8
           WHERE id = $9 AND event_id = $10 RETURNING *""",
        data.day_number, data.title, data.description, data.activities,
        data.meals_included, data.accommodation, data.distance_km, data.elevation_m,
        day_id, event_id
    )

    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Itinerary day not found")

    return ItineraryDayResponse(
        id=str(row["id"]),
        event_id=str(row["event_id"]),
        day_number=row["day_number"],
        title=row["title"],
        description=row["description"],
        activities=list(row.get("activities") or []),
        meals_included=list(row.get("meals_included") or []),
        accommodation=row.get("accommodation", "") or "",
        distance_km=row.get("distance_km", 0) or 0,
        elevation_m=row.get("elevation_m", 0) or 0,
    )


@router.delete("/{community_id}/events/{event_id}/itinerary/{day_id}", status_code=status.HTTP_200_OK)
async def delete_itinerary_day(
    community_id: str,
    event_id: str,
    day_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    await _require_admin(pool, community_id, user_id)

    result = await pool.execute(
        "DELETE FROM event_itinerary WHERE id = $1 AND event_id = $2",
        day_id, event_id
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Itinerary day not found")

    return {"detail": "Itinerary day deleted successfully"}


# ── Event Ride Sharing ────────────────────────────────────────────────────────

async def _build_ride_response(pool, ride_row, user_id: str) -> dict:
    """Build a full EventRideResponse dict from a DB row."""
    ride_id = str(ride_row["id"])

    # Driver info (include phone)
    driver = await pool.fetchrow(
        "SELECT name, profile_image_url, phone FROM users WHERE id = $1",
        ride_row["user_id"]
    )

    # Passengers with pickup coords, fare, and phone
    passengers_rows = await pool.fetch(
        """SELECT erp.id, erp.user_id, erp.created_at,
                  erp.pickup_lat, erp.pickup_lng, erp.pickup_location_name, erp.calculated_fare,
                  u.name, u.profile_image_url, u.phone
           FROM event_ride_passengers erp
           JOIN users u ON u.id = erp.user_id
           WHERE erp.ride_id = $1
           ORDER BY erp.created_at""",
        ride_id
    )

    is_driver = str(ride_row["user_id"]) == user_id
    is_passenger = any(str(p["user_id"]) == user_id for p in passengers_rows)

    # my_fare: fare for the requesting user if they are a passenger
    my_fare = 0.0
    for p in passengers_rows:
        if str(p["user_id"]) == user_id:
            my_fare = float(p["calculated_fare"] or 0)
            break

    passengers = [
        {
            "id": str(p["id"]),
            "user_id": str(p["user_id"]),
            "user_name": p["name"],
            "user_profile_image": p["profile_image_url"] or "",
            "user_phone": p["phone"] or "",
            "pickup_lat": float(p["pickup_lat"] or 0),
            "pickup_lng": float(p["pickup_lng"] or 0),
            "pickup_location_name": p["pickup_location_name"] or "",
            "calculated_fare": float(p["calculated_fare"] or 0),
            "joined_at": p["created_at"],
        }
        for p in passengers_rows
    ]

    rate_per_km = float(ride_row.get("rate_per_km") or 0)

    return {
        "id": ride_id,
        "event_id": str(ride_row["event_id"]),
        "user_id": str(ride_row["user_id"]),
        "driver_name": driver["name"] if driver else None,
        "driver_image": driver["profile_image_url"] if driver else "",
        "driver_phone": driver["phone"] if driver else "",
        "vehicle_type": ride_row["vehicle_type"],
        "vehicle_model": ride_row["vehicle_model"] or "",
        "vehicle_color": ride_row["vehicle_color"] or "",
        "total_seats": ride_row["total_seats"],
        "available_seats": ride_row["available_seats"],
        "start_location": ride_row["start_location"] or "",
        "start_lat": float(ride_row.get("start_lat") or 0),
        "start_lng": float(ride_row.get("start_lng") or 0),
        "drop_lat": float(ride_row.get("drop_lat") or 0),
        "drop_lng": float(ride_row.get("drop_lng") or 0),
        "start_time": ride_row["start_time"],
        "rate_per_km": rate_per_km,
        "total_distance_km": float(ride_row.get("total_distance_km") or 0),
        "route_polyline": ride_row.get("route_polyline") or "",
        "is_free": rate_per_km == 0,
        "notes": ride_row["notes"] or "",
        "is_driver": is_driver,
        "is_passenger": is_passenger,
        "my_fare": my_fare,
        "passengers": passengers,
        "created_at": ride_row["created_at"],
    }


@router.post("/{community_id}/events/{event_id}/rides", response_model=EventRideResponse, status_code=status.HTTP_201_CREATED)
async def create_event_ride(
    community_id: str,
    event_id: str,
    ride_data: EventRideCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    booking = await pool.fetchrow(
        "SELECT id FROM community_event_bookings WHERE event_id = $1 AND user_id = $2",
        event_id, user_id
    )
    if not booking:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You must be enrolled in this event to offer a ride")

    existing = await pool.fetchrow(
        "SELECT id FROM event_rides WHERE event_id = $1 AND user_id = $2",
        event_id, user_id
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You already have a ride offer for this event")

    # Get drop location from event venue
    event_row = await pool.fetchrow(
        "SELECT venue_lat, venue_lng FROM community_events WHERE id = $1", event_id
    )
    drop_lat = float(event_row["venue_lat"] or 0) if event_row else 0
    drop_lng = float(event_row["venue_lng"] or 0) if event_row else 0

    # Calculate total road distance and get route polyline
    total_distance = 0.0
    route_polyline = ""
    if ride_data.start_lat and ride_data.start_lng and drop_lat and drop_lng:
        total_distance, route_polyline = await _road_distance_km(
            ride_data.start_lat, ride_data.start_lng, drop_lat, drop_lng
        )

    row = await pool.fetchrow(
        """INSERT INTO event_rides
           (event_id, user_id, vehicle_type, vehicle_model, vehicle_color,
            total_seats, available_seats, start_location,
            start_lat, start_lng, drop_lat, drop_lng,
            start_time, rate_per_km, total_distance_km, notes, route_polyline)
           VALUES ($1,$2,$3,$4,$5,$6,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
           RETURNING *""",
        event_id, user_id,
        ride_data.vehicle_type, ride_data.vehicle_model, ride_data.vehicle_color,
        ride_data.total_seats,
        ride_data.start_location,
        ride_data.start_lat, ride_data.start_lng, drop_lat, drop_lng,
        ride_data.start_time, ride_data.rate_per_km, total_distance, ride_data.notes,
        route_polyline,
    )

    return await _build_ride_response(pool, row, user_id)


@router.get("/{community_id}/events/{event_id}/rides", response_model=List[EventRideResponse])
async def list_event_rides(
    community_id: str,
    event_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        "SELECT * FROM event_rides WHERE event_id = $1 ORDER BY start_time",
        event_id
    )
    return [await _build_ride_response(pool, row, user_id) for row in rows]


@router.post("/{community_id}/events/{event_id}/rides/{ride_id}/join", response_model=EventRideResponse)
async def join_event_ride(
    community_id: str,
    event_id: str,
    ride_id: str,
    join_data: JoinRideRequest,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    booking = await pool.fetchrow(
        "SELECT id FROM community_event_bookings WHERE event_id = $1 AND user_id = $2",
        event_id, user_id
    )
    if not booking:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You must be enrolled in this event")

    ride = await pool.fetchrow("SELECT * FROM event_rides WHERE id = $1 AND event_id = $2", ride_id, event_id)
    if not ride:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ride not found")

    if str(ride["user_id"]) == user_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You cannot join your own ride")

    if ride["available_seats"] <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No seats available")

    existing = await pool.fetchrow(
        "SELECT id FROM event_ride_passengers WHERE ride_id = $1 AND user_id = $2",
        ride_id, user_id
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You already joined this ride")

    # Calculate fare from pickup to drop using real road distance
    rate_per_km = float(ride.get("rate_per_km") or 0)
    calculated_fare = 0.0
    if rate_per_km > 0 and join_data.pickup_lat and join_data.pickup_lng:
        drop_lat = float(ride.get("drop_lat") or 0)
        drop_lng = float(ride.get("drop_lng") or 0)
        if drop_lat and drop_lng:
            dist, _ = await _road_distance_km(
                join_data.pickup_lat, join_data.pickup_lng, drop_lat, drop_lng
            )
            calculated_fare = round(dist * rate_per_km, 2)
    elif rate_per_km > 0:
        # No midpoint — charge full ride fare
        calculated_fare = round(float(ride.get("total_distance_km") or 0) * rate_per_km, 2)

    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                """INSERT INTO event_ride_passengers
                   (ride_id, user_id, pickup_lat, pickup_lng, pickup_location_name, calculated_fare)
                   VALUES ($1, $2, $3, $4, $5, $6)""",
                ride_id, user_id,
                join_data.pickup_lat, join_data.pickup_lng,
                join_data.pickup_location_name, calculated_fare
            )
            await conn.execute(
                "UPDATE event_rides SET available_seats = available_seats - 1 WHERE id = $1",
                ride_id
            )

    updated_ride = await pool.fetchrow("SELECT * FROM event_rides WHERE id = $1", ride_id)
    return await _build_ride_response(pool, updated_ride, user_id)


@router.delete("/{community_id}/events/{event_id}/rides/{ride_id}/leave", status_code=status.HTTP_200_OK)
async def leave_event_ride(
    community_id: str,
    event_id: str,
    ride_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    result = await pool.execute(
        "DELETE FROM event_ride_passengers WHERE ride_id = $1 AND user_id = $2",
        ride_id, user_id
    )
    if result == "DELETE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="You are not a passenger on this ride")

    await pool.execute(
        "UPDATE event_rides SET available_seats = available_seats + 1 WHERE id = $1",
        ride_id
    )
    return {"detail": "Left ride successfully"}


@router.delete("/{community_id}/events/{event_id}/rides/{ride_id}", status_code=status.HTTP_200_OK)
async def delete_event_ride(
    community_id: str,
    event_id: str,
    ride_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    ride = await pool.fetchrow("SELECT user_id FROM event_rides WHERE id = $1 AND event_id = $2", ride_id, event_id)
    if not ride:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ride not found")
    if str(ride["user_id"]) != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You can only delete your own ride")

    await pool.execute("DELETE FROM event_rides WHERE id = $1", ride_id)
    return {"detail": "Ride deleted successfully"}
