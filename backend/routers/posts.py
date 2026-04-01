from fastapi import APIRouter, Depends, HTTPException, status, Query, Request
from typing import List

from schemas.post import PostCreate, PostUpdate, PostResponse, CommentCreate, CommentResponse
from services.auth import get_current_user

router = APIRouter(prefix="/api/posts", tags=["posts"])


def _row_to_post_response(row, liked_post_ids: set = None) -> PostResponse:
    post_id = str(row["id"])
    return PostResponse(
        id=post_id,
        user_id=str(row["user_id"]),
        user_name=row.get("user_name") or "Unknown",
        user_profile_image=row.get("user_profile_image") or None,
        image_url=row["image_url"] or None,
        caption=row["caption"],
        media_type=row.get("media_type") or "image",
        video_url=row.get("video_url") or None,
        likes=[],
        likes_count=row.get("likes_count", 0),
        is_liked=post_id in (liked_post_ids or set()),
        comments_count=row.get("comments_count", 0),
        created_at=row["created_at"],
    )


@router.post("", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
async def create_post(
    post_data: PostCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        row = await pool.fetchrow(
            """
            INSERT INTO posts (user_id, image_url, caption, media_type, video_url)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
            """,
            user_id,
            post_data.image_url or "",
            post_data.caption,
            post_data.media_type or "image",
            post_data.video_url or "",
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create post: {str(e)}",
        )

    return PostResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        user_profile_image=current_user.get("profile_image_url") or None,
        image_url=row["image_url"] or None,
        caption=row["caption"],
        media_type=row.get("media_type") or "image",
        video_url=row.get("video_url") or None,
        likes=[],
        likes_count=0,
        is_liked=False,
        created_at=row["created_at"],
    )


@router.get("", response_model=List[PostResponse])
async def get_feed(
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """
        SELECT p.*,
               u.name AS user_name,
               u.profile_image_url AS user_profile_image,
               (SELECT COUNT(*) FROM comments WHERE post_id = p.id) AS comments_count
        FROM posts p
        JOIN users u ON p.user_id = u.id
        ORDER BY p.created_at DESC
        OFFSET $1 LIMIT $2
        """,
        skip,
        limit,
    )

    # Get set of post IDs the current user has liked
    if rows:
        post_ids = [row["id"] for row in rows]
        liked_rows = await pool.fetch(
            "SELECT post_id FROM post_likes WHERE user_id = $1 AND post_id = ANY($2)",
            user_id,
            post_ids,
        )
        liked_post_ids = {str(r["post_id"]) for r in liked_rows}
    else:
        liked_post_ids = set()

    return [_row_to_post_response(row, liked_post_ids) for row in rows]


@router.get("/{post_id}", response_model=PostResponse)
async def get_post(
    post_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        row = await pool.fetchrow(
            """
            SELECT p.*,
                   u.name AS user_name,
                   u.profile_image_url AS user_profile_image,
                   (SELECT COUNT(*) FROM comments WHERE post_id = p.id) AS comments_count
            FROM posts p
            JOIN users u ON p.user_id = u.id
            WHERE p.id = $1
            """,
            post_id,
        )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid post ID format",
        )

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found",
        )

    liked = await pool.fetchrow(
        "SELECT id FROM post_likes WHERE post_id = $1 AND user_id = $2",
        post_id,
        user_id,
    )

    return PostResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        user_name=row["user_name"],
        user_profile_image=row["user_profile_image"] or None,
        image_url=row["image_url"] or None,
        caption=row["caption"],
        media_type=row.get("media_type") or "image",
        video_url=row.get("video_url") or None,
        likes=[],
        likes_count=row["likes_count"],
        is_liked=liked is not None,
        comments_count=row.get("comments_count", 0),
        created_at=row["created_at"],
    )


@router.post("/{post_id}/like", response_model=PostResponse)
async def toggle_like(
    post_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Check post exists
    try:
        post = await pool.fetchrow("SELECT id FROM posts WHERE id = $1", post_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid post ID format",
        )

    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found",
        )

    # Check if already liked
    existing_like = await pool.fetchrow(
        "SELECT id FROM post_likes WHERE post_id = $1 AND user_id = $2",
        post_id,
        user_id,
    )

    if existing_like:
        # Unlike: remove the like and decrement count
        await pool.execute(
            "DELETE FROM post_likes WHERE post_id = $1 AND user_id = $2",
            post_id,
            user_id,
        )
        await pool.execute(
            "UPDATE posts SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = $1",
            post_id,
        )
    else:
        # Like: insert and increment count
        await pool.execute(
            "INSERT INTO post_likes (post_id, user_id) VALUES ($1, $2)",
            post_id,
            user_id,
        )
        await pool.execute(
            "UPDATE posts SET likes_count = likes_count + 1 WHERE id = $1",
            post_id,
        )

    # Return updated post
    row = await pool.fetchrow(
        """
        SELECT p.*,
               u.name AS user_name,
               u.profile_image_url AS user_profile_image,
               (SELECT COUNT(*) FROM comments WHERE post_id = p.id) AS comments_count
        FROM posts p
        JOIN users u ON p.user_id = u.id
        WHERE p.id = $1
        """,
        post_id,
    )

    is_liked = existing_like is None  # toggled
    return PostResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        user_name=row["user_name"],
        user_profile_image=row["user_profile_image"] or None,
        image_url=row["image_url"] or None,
        caption=row["caption"],
        media_type=row.get("media_type") or "image",
        video_url=row.get("video_url") or None,
        likes=[],
        likes_count=row["likes_count"],
        is_liked=is_liked,
        comments_count=row.get("comments_count", 0),
        created_at=row["created_at"],
    )


@router.post("/{post_id}/comment", response_model=CommentResponse, status_code=status.HTTP_201_CREATED)
async def add_comment(
    post_id: str,
    comment_data: CommentCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Check post exists
    try:
        post = await pool.fetchrow("SELECT id FROM posts WHERE id = $1", post_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid post ID format",
        )

    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found",
        )

    try:
        row = await pool.fetchrow(
            """
            INSERT INTO comments (post_id, user_id, text)
            VALUES ($1, $2, $3)
            RETURNING *
            """,
            post_id,
            user_id,
            comment_data.text,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create comment: {str(e)}",
        )

    return CommentResponse(
        id=str(row["id"]),
        post_id=str(row["post_id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        user_profile_image=current_user.get("profile_image_url") or None,
        text=row["text"],
        likes_count=0,
        is_liked=False,
        replies_count=0,
        created_at=row["created_at"],
    )


@router.get("/{post_id}/comments", response_model=List[CommentResponse])
async def get_comments(
    post_id: str,
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    # Check post exists
    try:
        post = await pool.fetchrow("SELECT id FROM posts WHERE id = $1", post_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid post ID format",
        )

    if not post:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Post not found",
        )

    user_id = current_user["id"]

    rows = await pool.fetch(
        """
        SELECT c.*, u.name AS user_name, u.profile_image_url AS user_profile_image,
               (SELECT COUNT(*) FROM comment_likes WHERE comment_id = c.id) AS likes_count,
               EXISTS(SELECT 1 FROM comment_likes WHERE comment_id = c.id AND user_id = $2) AS is_liked,
               (SELECT COUNT(*) FROM comment_replies WHERE comment_id = c.id) AS replies_count
        FROM comments c
        JOIN users u ON c.user_id = u.id
        WHERE c.post_id = $1
        ORDER BY c.created_at DESC
        OFFSET $3 LIMIT $4
        """,
        post_id,
        user_id,
        skip,
        limit,
    )

    return [
        CommentResponse(
            id=str(row["id"]),
            post_id=str(row["post_id"]),
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            user_profile_image=row.get("user_profile_image") or None,
            text=row["text"],
            likes_count=row.get("likes_count", 0),
            is_liked=row.get("is_liked", False),
            replies_count=row.get("replies_count", 0),
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.post("/{post_id}/comments/{comment_id}/like")
async def toggle_comment_like(
    post_id: str, comment_id: str, request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    existing = await pool.fetchrow(
        "SELECT id FROM comment_likes WHERE comment_id = $1 AND user_id = $2",
        comment_id, user_id
    )

    if existing:
        await pool.execute("DELETE FROM comment_likes WHERE comment_id = $1 AND user_id = $2", comment_id, user_id)
        is_liked = False
    else:
        await pool.execute("INSERT INTO comment_likes (comment_id, user_id) VALUES ($1, $2)", comment_id, user_id)
        is_liked = True

    likes_count = await pool.fetchval("SELECT COUNT(*) FROM comment_likes WHERE comment_id = $1", comment_id)
    return {"is_liked": is_liked, "likes_count": likes_count}


@router.post("/{post_id}/comments/{comment_id}/reply")
async def reply_to_comment(
    post_id: str, comment_id: str, request: Request,
    comment_data: CommentCreate,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    row = await pool.fetchrow(
        "INSERT INTO comment_replies (comment_id, user_id, text) VALUES ($1, $2, $3) RETURNING *",
        comment_id, user_id, comment_data.text
    )

    return {
        "id": str(row["id"]),
        "comment_id": str(row["comment_id"]),
        "user_id": str(row["user_id"]),
        "user_name": current_user["name"],
        "user_profile_image": current_user.get("profile_image_url"),
        "text": row["text"],
        "created_at": row["created_at"].isoformat(),
    }


@router.get("/{post_id}/comments/{comment_id}/replies")
async def get_comment_replies(
    post_id: str, comment_id: str, request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    rows = await pool.fetch(
        """SELECT cr.*, u.name AS user_name, u.profile_image_url AS user_profile_image
           FROM comment_replies cr
           JOIN users u ON cr.user_id = u.id
           WHERE cr.comment_id = $1
           ORDER BY cr.created_at ASC""",
        comment_id
    )

    return [
        {
            "id": str(row["id"]),
            "comment_id": str(row["comment_id"]),
            "user_id": str(row["user_id"]),
            "user_name": row["user_name"],
            "user_profile_image": row.get("user_profile_image"),
            "text": row["text"],
            "created_at": row["created_at"].isoformat(),
        }
        for row in rows
    ]


@router.put("/{post_id}", response_model=PostResponse)
async def update_post(
    post_id: str,
    update_data: PostUpdate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Check post exists and belongs to user
    try:
        post = await pool.fetchrow("SELECT * FROM posts WHERE id = $1", post_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid post ID")

    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    if str(post["user_id"]) != user_id:
        raise HTTPException(status_code=403, detail="You can only edit your own posts")

    # Build update
    set_parts = []
    params = []
    idx = 1

    if update_data.caption is not None:
        set_parts.append(f"caption = ${idx}")
        params.append(update_data.caption)
        idx += 1
    if update_data.image_url is not None:
        set_parts.append(f"image_url = ${idx}")
        params.append(update_data.image_url)
        idx += 1
    if update_data.video_url is not None:
        set_parts.append(f"video_url = ${idx}")
        params.append(update_data.video_url)
        idx += 1

    if not set_parts:
        raise HTTPException(status_code=400, detail="Nothing to update")

    params.append(post_id)
    query = f"UPDATE posts SET {', '.join(set_parts)} WHERE id = ${idx} RETURNING *"
    row = await pool.fetchrow(query, *params)

    return PostResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        user_profile_image=current_user.get("profile_image_url") or None,
        image_url=row["image_url"] or None,
        caption=row["caption"],
        media_type=row.get("media_type") or "image",
        video_url=row.get("video_url") or None,
        likes=[],
        likes_count=row["likes_count"],
        is_liked=False,
        comments_count=0,
        created_at=row["created_at"],
    )


@router.delete("/{post_id}", status_code=status.HTTP_200_OK)
async def delete_post(
    post_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Check post exists and belongs to user
    try:
        post = await pool.fetchrow("SELECT * FROM posts WHERE id = $1", post_id)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid post ID")

    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    if str(post["user_id"]) != user_id:
        raise HTTPException(status_code=403, detail="You can only delete your own posts")

    # Delete post (cascade deletes likes and comments)
    await pool.execute("DELETE FROM posts WHERE id = $1", post_id)

    return {"message": "Post deleted successfully"}
