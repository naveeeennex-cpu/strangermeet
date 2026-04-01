from fastapi import APIRouter, Depends, HTTPException, status, Request
from typing import List
from collections import OrderedDict

from schemas.story import StoryCreate, StoryResponse, UserStories, StoryReplyCreate, StoryReplyResponse
from services.auth import get_current_user

router = APIRouter(prefix="/api/stories", tags=["stories"])


def _row_to_story_response(row, viewed_story_ids: set = None) -> StoryResponse:
    story_id = str(row["id"])
    return StoryResponse(
        id=story_id,
        user_id=str(row["user_id"]),
        user_name=row.get("user_name") or "Unknown",
        user_image=row.get("user_image") or None,
        image_url=row["image_url"],
        caption=row.get("caption") or "",
        media_type=row.get("media_type") or "image",
        video_url=row.get("video_url") or None,
        views_count=row.get("views_count", 0),
        is_viewed=story_id in (viewed_story_ids or set()),
        created_at=row["created_at"],
        expires_at=row["expires_at"],
    )


@router.post("", response_model=StoryResponse, status_code=status.HTTP_201_CREATED)
async def create_story(
    story_data: StoryCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        row = await pool.fetchrow(
            """
            INSERT INTO stories (user_id, image_url, caption, media_type, video_url)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
            """,
            user_id,
            story_data.image_url,
            story_data.caption,
            getattr(story_data, 'media_type', 'image') or 'image',
            getattr(story_data, 'video_url', '') or '',
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create story: {str(e)}",
        )

    return StoryResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        user_image=current_user.get("profile_image_url") or None,
        image_url=row["image_url"],
        caption=row["caption"] or "",
        media_type=row.get("media_type") or "image",
        video_url=row.get("video_url") or None,
        views_count=0,
        is_viewed=False,
        created_at=row["created_at"],
        expires_at=row["expires_at"],
    )


@router.get("/my", response_model=List[StoryResponse])
async def get_my_stories(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """
        SELECT s.*,
               u.name AS user_name,
               u.profile_image_url AS user_image,
               COALESCE(sv.view_count, 0) AS views_count
        FROM stories s
        JOIN users u ON s.user_id = u.id
        LEFT JOIN (
            SELECT story_id, COUNT(*) AS view_count
            FROM story_views
            GROUP BY story_id
        ) sv ON sv.story_id = s.id
        WHERE s.user_id = $1 AND s.expires_at > NOW()
        ORDER BY s.created_at DESC
        """,
        user_id,
    )

    return [_row_to_story_response(row, set()) for row in rows]


@router.get("", response_model=List[UserStories])
async def get_all_stories(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """
        SELECT s.*,
               u.name AS user_name,
               u.profile_image_url AS user_image,
               COALESCE(sv.view_count, 0) AS views_count
        FROM stories s
        JOIN users u ON s.user_id = u.id
        LEFT JOIN (
            SELECT story_id, COUNT(*) AS view_count
            FROM story_views
            GROUP BY story_id
        ) sv ON sv.story_id = s.id
        WHERE s.expires_at > NOW()
        ORDER BY s.created_at DESC
        """
    )

    if not rows:
        return []

    # Get viewed story IDs for current user
    story_ids = [row["id"] for row in rows]
    viewed_rows = await pool.fetch(
        "SELECT story_id FROM story_views WHERE user_id = $1 AND story_id = ANY($2)",
        user_id,
        story_ids,
    )
    viewed_story_ids = {str(r["story_id"]) for r in viewed_rows}

    # Group stories by user
    user_groups: OrderedDict[str, dict] = OrderedDict()
    for row in rows:
        uid = str(row["user_id"])
        story = _row_to_story_response(row, viewed_story_ids)
        if uid not in user_groups:
            user_groups[uid] = {
                "user_id": uid,
                "user_name": row.get("user_name") or "Unknown",
                "user_image": row.get("user_image") or None,
                "stories": [],
                "has_unviewed": False,
            }
        user_groups[uid]["stories"].append(story)
        if not story.is_viewed:
            user_groups[uid]["has_unviewed"] = True

    return [UserStories(**data) for data in user_groups.values()]


@router.get("/{story_id}", response_model=StoryResponse)
async def get_story(
    story_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        row = await pool.fetchrow(
            """
            SELECT s.*,
                   u.name AS user_name,
                   u.profile_image_url AS user_image,
                   COALESCE(sv.view_count, 0) AS views_count
            FROM stories s
            JOIN users u ON s.user_id = u.id
            LEFT JOIN (
                SELECT story_id, COUNT(*) AS view_count
                FROM story_views
                GROUP BY story_id
            ) sv ON sv.story_id = s.id
            WHERE s.id = $1 AND s.expires_at > NOW()
            """,
            story_id,
        )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid story ID format",
        )

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Story not found or expired",
        )

    # Mark as viewed (ignore if already viewed)
    try:
        await pool.execute(
            "INSERT INTO story_views (story_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
            story_id,
            user_id,
        )
    except Exception:
        pass  # non-critical

    viewed = await pool.fetchrow(
        "SELECT id FROM story_views WHERE story_id = $1 AND user_id = $2",
        story_id,
        user_id,
    )

    story = _row_to_story_response(row, {str(row["id"])} if viewed else set())
    return story


@router.post("/{story_id}/reply", response_model=StoryReplyResponse, status_code=status.HTTP_201_CREATED)
async def reply_to_story(
    story_id: str,
    reply_data: StoryReplyCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Check story exists and is not expired
    try:
        story = await pool.fetchrow(
            "SELECT id, user_id FROM stories WHERE id = $1 AND expires_at > NOW()",
            story_id,
        )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid story ID format",
        )

    if not story:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Story not found or expired",
        )

    # Insert reply
    try:
        row = await pool.fetchrow(
            """
            INSERT INTO story_replies (story_id, user_id, message)
            VALUES ($1, $2, $3)
            RETURNING *
            """,
            story_id,
            user_id,
            reply_data.message,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to reply to story: {str(e)}",
        )

    # Also send as a direct message to the story owner
    story_owner_id = str(story["user_id"])
    if story_owner_id != user_id:
        try:
            await pool.execute(
                """
                INSERT INTO messages (sender_id, receiver_id, message)
                VALUES ($1, $2, $3)
                """,
                user_id,
                story_owner_id,
                f"[Story Reply] {reply_data.message}",
            )
        except Exception:
            pass  # non-critical

    return StoryReplyResponse(
        id=str(row["id"]),
        story_id=str(row["story_id"]),
        user_id=str(row["user_id"]),
        user_name=current_user["name"],
        user_image=current_user.get("profile_image_url") or None,
        message=row["message"],
        created_at=row["created_at"],
    )


@router.delete("/{story_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_story(
    story_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        story = await pool.fetchrow(
            "SELECT id, user_id FROM stories WHERE id = $1",
            story_id,
        )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid story ID format",
        )

    if not story:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Story not found",
        )

    if str(story["user_id"]) != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only delete your own stories",
        )

    await pool.execute("DELETE FROM stories WHERE id = $1", story_id)
