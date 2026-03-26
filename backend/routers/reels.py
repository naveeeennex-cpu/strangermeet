from fastapi import APIRouter, Depends, HTTPException, status, Query, Request
from typing import List

from schemas.reel import ReelCreate, ReelResponse, ReelCommentCreate, ReelCommentResponse
from services.auth import get_current_user

router = APIRouter(prefix="/api/reels", tags=["reels"])


@router.post("", response_model=ReelResponse, status_code=status.HTTP_201_CREATED)
async def create_reel(
    data: ReelCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        row = await pool.fetchrow(
            """INSERT INTO reels (user_id, media_url, media_type, caption)
               VALUES ($1, $2, $3, $4) RETURNING *""",
            user_id, data.media_url, data.media_type, data.caption
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create reel: {str(e)}",
        )

    return ReelResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        user_profile_image=current_user.get("profile_image_url"),
        media_url=row["media_url"],
        media_type=row["media_type"],
        caption=row["caption"],
        likes_count=0,
        is_liked=False,
        comments_count=0,
        created_at=row["created_at"],
    )


@router.get("", response_model=List[ReelResponse])
async def get_reels_feed(
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """SELECT r.*,
                  u.name AS user_name,
                  u.profile_image_url AS user_profile_image
           FROM reels r
           JOIN users u ON r.user_id = u.id
           ORDER BY r.created_at DESC
           OFFSET $1 LIMIT $2""",
        skip, limit
    )

    if rows:
        reel_ids = [row["id"] for row in rows]
        liked_rows = await pool.fetch(
            "SELECT reel_id FROM reel_likes WHERE user_id = $1 AND reel_id = ANY($2)",
            user_id, reel_ids
        )
        liked_ids = {str(r["reel_id"]) for r in liked_rows}
    else:
        liked_ids = set()

    return [
        ReelResponse(
            id=str(row["id"]),
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            user_profile_image=row.get("user_profile_image"),
            media_url=row["media_url"],
            media_type=row["media_type"],
            caption=row["caption"],
            likes_count=row["likes_count"],
            is_liked=str(row["id"]) in liked_ids,
            comments_count=row["comments_count"],
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.get("/{reel_id}", response_model=ReelResponse)
async def get_reel(
    reel_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        row = await pool.fetchrow(
            """SELECT r.*,
                      u.name AS user_name,
                      u.profile_image_url AS user_profile_image
               FROM reels r
               JOIN users u ON r.user_id = u.id
               WHERE r.id = $1""",
            reel_id
        )
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid reel ID format")

    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reel not found")

    liked = await pool.fetchrow(
        "SELECT id FROM reel_likes WHERE reel_id = $1 AND user_id = $2",
        reel_id, user_id
    )

    return ReelResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        user_name=row["user_name"],
        user_profile_image=row.get("user_profile_image"),
        media_url=row["media_url"],
        media_type=row["media_type"],
        caption=row["caption"],
        likes_count=row["likes_count"],
        is_liked=liked is not None,
        comments_count=row["comments_count"],
        created_at=row["created_at"],
    )


@router.post("/{reel_id}/like", response_model=ReelResponse)
async def toggle_reel_like(
    reel_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        reel = await pool.fetchrow("SELECT id FROM reels WHERE id = $1", reel_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid reel ID format")

    if not reel:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reel not found")

    existing_like = await pool.fetchrow(
        "SELECT id FROM reel_likes WHERE reel_id = $1 AND user_id = $2",
        reel_id, user_id
    )

    if existing_like:
        await pool.execute("DELETE FROM reel_likes WHERE reel_id = $1 AND user_id = $2", reel_id, user_id)
        await pool.execute("UPDATE reels SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = $1", reel_id)
    else:
        await pool.execute("INSERT INTO reel_likes (reel_id, user_id) VALUES ($1, $2)", reel_id, user_id)
        await pool.execute("UPDATE reels SET likes_count = likes_count + 1 WHERE id = $1", reel_id)

    row = await pool.fetchrow(
        """SELECT r.*,
                  u.name AS user_name,
                  u.profile_image_url AS user_profile_image
           FROM reels r
           JOIN users u ON r.user_id = u.id
           WHERE r.id = $1""",
        reel_id
    )

    return ReelResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        user_name=row["user_name"],
        user_profile_image=row.get("user_profile_image"),
        media_url=row["media_url"],
        media_type=row["media_type"],
        caption=row["caption"],
        likes_count=row["likes_count"],
        is_liked=existing_like is None,
        comments_count=row["comments_count"],
        created_at=row["created_at"],
    )


@router.post("/{reel_id}/comment", response_model=ReelCommentResponse, status_code=status.HTTP_201_CREATED)
async def add_reel_comment(
    reel_id: str,
    data: ReelCommentCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        reel = await pool.fetchrow("SELECT id FROM reels WHERE id = $1", reel_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid reel ID format")

    if not reel:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reel not found")

    row = await pool.fetchrow(
        "INSERT INTO reel_comments (reel_id, user_id, text) VALUES ($1, $2, $3) RETURNING *",
        reel_id, user_id, data.text
    )

    # Increment comments_count
    await pool.execute(
        "UPDATE reels SET comments_count = comments_count + 1 WHERE id = $1",
        reel_id
    )

    return ReelCommentResponse(
        id=str(row["id"]),
        reel_id=str(row["reel_id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        text=row["text"],
        created_at=row["created_at"],
    )


@router.get("/{reel_id}/comments", response_model=List[ReelCommentResponse])
async def get_reel_comments(
    reel_id: str,
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    try:
        reel = await pool.fetchrow("SELECT id FROM reels WHERE id = $1", reel_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid reel ID format")

    if not reel:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reel not found")

    rows = await pool.fetch(
        """SELECT rc.*, u.name AS user_name
           FROM reel_comments rc
           JOIN users u ON rc.user_id = u.id
           WHERE rc.reel_id = $1
           ORDER BY rc.created_at DESC
           OFFSET $2 LIMIT $3""",
        reel_id, skip, limit
    )

    return [
        ReelCommentResponse(
            id=str(row["id"]),
            reel_id=str(row["reel_id"]),
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            text=row["text"],
            created_at=row["created_at"],
        )
        for row in rows
    ]
