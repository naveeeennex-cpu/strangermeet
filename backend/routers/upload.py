"""
Unified file upload endpoint.
Handles image uploads for posts, profiles, stories, reels, communities, events.
"""
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status, Request
from typing import Optional

from services.auth import get_current_user
from services.storage import storage

router = APIRouter(prefix="/api/upload", tags=["upload"])

MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
MAX_VIDEO_FILE_SIZE = 100 * 1024 * 1024  # 100MB for videos
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/gif", "image/webp"}
ALLOWED_VIDEO_TYPES = {"video/mp4", "video/quicktime"}
ALLOWED_AUDIO_TYPES = {"audio/aac", "audio/mp4", "audio/m4a", "audio/mpeg", "audio/x-m4a"}


@router.post("")
async def upload_file(
    file: UploadFile = File(...),
    folder: str = Form("posts"),
    current_user: dict = Depends(get_current_user),
):
    """Upload a file to GCS. Returns the public URL."""

    # Validate content type
    content_type = file.content_type or ""
    if content_type not in ALLOWED_IMAGE_TYPES and content_type not in ALLOWED_VIDEO_TYPES and content_type not in ALLOWED_AUDIO_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"File type '{content_type}' not allowed. Use JPEG, PNG, GIF, WebP, MP4, or M4A/AAC audio.",
        )

    # Read file
    file_data = await file.read()

    # Validate size
    if len(file_data) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"File too large. Maximum size is {MAX_FILE_SIZE // (1024*1024)}MB.",
        )

    # Upload to GCS
    try:
        url = await storage.upload_file(
            file_data=file_data,
            original_filename=file.filename or "upload.jpg",
            folder=folder,
        )
        return {"url": url, "filename": file.filename, "folder": folder}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Upload failed: {str(e)}",
        )


@router.post("/post")
async def upload_and_create_post(
    request: Request,
    caption: str = Form(""),
    media_type: str = Form("image"),
    community_id: Optional[str] = Form(None),
    image: Optional[UploadFile] = File(None),
    video: Optional[UploadFile] = File(None),
    current_user: dict = Depends(get_current_user),
):
    """Upload image or video and create a post in one request."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    image_url = ""
    video_url = ""

    if media_type == "video" and video:
        # Upload video
        file_data = await video.read()
        if len(file_data) > MAX_VIDEO_FILE_SIZE:
            raise HTTPException(status_code=400, detail="Video too large (max 100MB)")

        try:
            video_url = await storage.upload_file(
                file_data=file_data,
                original_filename=video.filename or "post.mp4",
                folder="posts/videos",
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")
    elif image:
        # Upload image
        file_data = await image.read()
        if len(file_data) > MAX_FILE_SIZE:
            raise HTTPException(status_code=400, detail="File too large (max 10MB)")

        try:
            image_url = await storage.upload_file(
                file_data=file_data,
                original_filename=image.filename or "post.jpg",
                folder="posts",
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

    # Create post in DB
    row = await pool.fetchrow(
        """
        INSERT INTO posts (user_id, image_url, caption, media_type, video_url, community_id)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING *
        """,
        user_id,
        image_url,
        caption,
        media_type,
        video_url,
        community_id,
    )

    return {
        "id": str(row["id"]),
        "user_id": str(row["user_id"]),
        "user_name": current_user["name"],
        "user_profile_image": current_user.get("profile_image_url"),
        "image_url": image_url,
        "caption": caption,
        "media_type": media_type,
        "video_url": video_url,
        "likes_count": 0,
        "is_liked": False,
        "comments_count": 0,
        "created_at": row["created_at"].isoformat(),
    }


@router.post("/profile-image")
async def upload_profile_image(
    request: Request,
    image: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    """Upload and update profile image."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    file_data = await image.read()
    if len(file_data) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail="File too large (max 10MB)")

    try:
        image_url = await storage.upload_file(
            file_data=file_data,
            original_filename=image.filename or "profile.jpg",
            folder="profiles",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

    # Update user profile
    await pool.execute(
        "UPDATE users SET profile_image_url = $1 WHERE id = $2",
        image_url,
        user_id,
    )

    return {"url": image_url}


@router.post("/cover-image")
async def upload_cover_image(
    request: Request,
    image: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    """Upload and update cover image."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    file_data = await image.read()
    if len(file_data) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail="File too large (max 10MB)")

    try:
        image_url = await storage.upload_file(
            file_data=file_data,
            original_filename=image.filename or "cover.jpg",
            folder="profiles",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

    await pool.execute(
        "UPDATE users SET cover_image_url = $1 WHERE id = $2",
        image_url,
        user_id,
    )

    return {"url": image_url}


@router.post("/story")
async def upload_story(
    request: Request,
    caption: str = Form(""),
    media_type: str = Form("image"),
    image: Optional[UploadFile] = File(None),
    video: Optional[UploadFile] = File(None),
    current_user: dict = Depends(get_current_user),
):
    """Upload image or video and create a story."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    image_url = ""
    video_url = ""

    if media_type == "video" and video:
        # Upload video
        file_data = await video.read()
        if len(file_data) > MAX_VIDEO_FILE_SIZE:
            raise HTTPException(status_code=400, detail="Video too large (max 100MB)")

        try:
            video_url = await storage.upload_file(
                file_data=file_data,
                original_filename=video.filename or "story.mp4",
                folder="stories/videos",
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")
        # Use a placeholder for image_url since the column is NOT NULL
        image_url = video_url
    elif image:
        file_data = await image.read()
        if len(file_data) > MAX_FILE_SIZE:
            raise HTTPException(status_code=400, detail="File too large (max 10MB)")

        try:
            image_url = await storage.upload_file(
                file_data=file_data,
                original_filename=image.filename or "story.jpg",
                folder="stories",
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")
    else:
        raise HTTPException(status_code=400, detail="No file provided")

    row = await pool.fetchrow(
        """
        INSERT INTO stories (user_id, image_url, caption, media_type, video_url)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING *
        """,
        user_id,
        image_url,
        caption,
        media_type,
        video_url,
    )

    return {
        "id": str(row["id"]),
        "user_id": str(row["user_id"]),
        "image_url": image_url,
        "caption": caption,
        "media_type": media_type,
        "video_url": video_url,
        "created_at": row["created_at"].isoformat(),
    }
