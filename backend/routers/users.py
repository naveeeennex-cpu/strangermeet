from fastapi import APIRouter, Depends, HTTPException, status, Query, Request
from typing import List, Optional

from schemas.user import UserResponse, UserUpdate
from schemas.post import PostResponse
from services.auth import get_current_user

router = APIRouter(prefix="/api/users", tags=["users"])


def _row_to_user_response(row) -> UserResponse:
    return UserResponse(
        id=str(row["id"]),
        name=row["name"],
        email=row["email"],
        username=row.get("username") or None,
        bio=row["bio"] or "",
        phone=row.get("phone", "") or "",
        interests=list(row["interests"]) if row["interests"] else [],
        profile_image_url=row["profile_image_url"] or None,
        cover_image_url=row.get("cover_image_url") or None,
        role=row.get("role", "customer") or "customer",
        occupation=row.get("occupation", "") or "",
        college_name=row.get("college_name", "") or "",
        company_name=row.get("company_name", "") or "",
        created_at=row["created_at"],
    )


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: dict = Depends(get_current_user)):
    return UserResponse(
        id=current_user["id"],
        name=current_user["name"],
        email=current_user["email"],
        username=current_user.get("username") or None,
        bio=current_user.get("bio") or "",
        phone=current_user.get("phone", "") or "",
        interests=list(current_user["interests"]) if current_user.get("interests") else [],
        profile_image_url=current_user.get("profile_image_url") or None,
        cover_image_url=current_user.get("cover_image_url") or None,
        role=current_user.get("role", "customer") or "customer",
        occupation=current_user.get("occupation", "") or "",
        college_name=current_user.get("college_name", "") or "",
        company_name=current_user.get("company_name", "") or "",
        created_at=current_user["created_at"],
    )


@router.put("/me", response_model=UserResponse)
async def update_me(
    update_data: UserUpdate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    # Build dynamic update
    set_parts = []
    params = []
    param_idx = 1

    if update_data.bio is not None:
        set_parts.append(f"bio = ${param_idx}")
        params.append(update_data.bio)
        param_idx += 1
    if update_data.phone is not None:
        set_parts.append(f"phone = ${param_idx}")
        params.append(update_data.phone)
        param_idx += 1
    if update_data.interests is not None:
        set_parts.append(f"interests = ${param_idx}")
        params.append(update_data.interests)
        param_idx += 1
    if update_data.profile_image_url is not None:
        set_parts.append(f"profile_image_url = ${param_idx}")
        params.append(update_data.profile_image_url)
        param_idx += 1
    if update_data.username is not None:
        # Check uniqueness of username
        new_username = update_data.username.lower()
        existing_username = await pool.fetchrow(
            "SELECT id FROM users WHERE username = $1 AND id != $2",
            new_username,
            current_user["id"],
        )
        if existing_username:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already taken",
            )
        set_parts.append(f"username = ${param_idx}")
        params.append(new_username)
        param_idx += 1

    if not set_parts:
        # Nothing to update, return current user
        return UserResponse(
            id=current_user["id"],
            name=current_user["name"],
            email=current_user["email"],
            username=current_user.get("username") or None,
            bio=current_user.get("bio") or "",
            phone=current_user.get("phone", "") or "",
            interests=list(current_user["interests"]) if current_user.get("interests") else [],
            profile_image_url=current_user.get("profile_image_url") or None,
            cover_image_url=current_user.get("cover_image_url") or None,
            role=current_user.get("role", "customer") or "customer",
            occupation=current_user.get("occupation", "") or "",
            college_name=current_user.get("college_name", "") or "",
            company_name=current_user.get("company_name", "") or "",
            created_at=current_user["created_at"],
        )

    params.append(current_user["id"])
    query = f"UPDATE users SET {', '.join(set_parts)} WHERE id = ${param_idx} RETURNING *"

    try:
        row = await pool.fetchrow(query, *params)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update user: {str(e)}",
        )

    return _row_to_user_response(row)


@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    try:
        row = await pool.fetchrow("SELECT * FROM users WHERE id = $1", user_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid user ID format",
        )

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return _row_to_user_response(row)


@router.get("/{user_id}/posts", response_model=List[PostResponse])
async def get_user_posts(
    user_id: str,
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    # Verify user exists
    try:
        user = await pool.fetchrow("SELECT id FROM users WHERE id = $1", user_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid user ID format",
        )

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    rows = await pool.fetch(
        """
        SELECT p.*,
               u.name AS user_name,
               u.profile_image_url AS user_profile_image,
               (SELECT COUNT(*) FROM comments WHERE post_id = p.id) AS comments_count
        FROM posts p
        JOIN users u ON p.user_id = u.id
        WHERE p.user_id = $1
        ORDER BY p.created_at DESC
        OFFSET $2 LIMIT $3
        """,
        user_id,
        skip,
        limit,
    )

    # Get set of post IDs the current user has liked
    if rows:
        post_ids = [row["id"] for row in rows]
        liked_rows = await pool.fetch(
            "SELECT post_id FROM post_likes WHERE user_id = $1 AND post_id = ANY($2)",
            current_user["id"],
            post_ids,
        )
        liked_post_ids = {str(r["post_id"]) for r in liked_rows}
    else:
        liked_post_ids = set()

    return [
        PostResponse(
            id=str(row["id"]),
            user_id=str(row["user_id"]),
            user_name=row.get("user_name") or "Unknown",
            user_profile_image=row.get("user_profile_image") or None,
            image_url=row["image_url"] or None,
            caption=row["caption"],
            likes=[],
            likes_count=row.get("likes_count", 0),
            is_liked=str(row["id"]) in liked_post_ids,
            comments_count=row.get("comments_count", 0),
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.get("", response_model=List[UserResponse])
async def search_users(
    request: Request,
    q: Optional[str] = Query(None, description="Search by name or interest"),
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    if q:
        search_pattern = f"%{q}%"
        rows = await pool.fetch(
            """
            SELECT * FROM users
            WHERE name ILIKE $1 OR EXISTS (
                SELECT 1 FROM unnest(interests) AS interest
                WHERE interest ILIKE $1
            )
            ORDER BY created_at DESC
            OFFSET $2 LIMIT $3
            """,
            search_pattern,
            skip,
            limit,
        )
    else:
        rows = await pool.fetch(
            "SELECT * FROM users ORDER BY created_at DESC OFFSET $1 LIMIT $2",
            skip,
            limit,
        )

    return [_row_to_user_response(row) for row in rows]
