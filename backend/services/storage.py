"""
Supabase Storage service.
Handles file uploads for posts, profiles, stories, reels, communities, events.
Public bucket 'media' — all uploaded files are publicly accessible.
"""
import uuid
from datetime import datetime, timezone

import httpx
from config import settings


class SupabaseStorage:
    """Upload files to Supabase Storage."""

    SUPABASE_URL = settings.SUPABASE_URL
    SERVICE_KEY = settings.SUPABASE_SERVICE_KEY
    BUCKET = settings.SUPABASE_BUCKET  # "media"

    CONTENT_TYPES = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".gif": "image/gif",
        ".webp": "image/webp",
        ".mp4": "video/mp4",
        ".mov": "video/quicktime",
        ".m4a": "audio/mp4",
        ".aac": "audio/aac",
        ".mp3": "audio/mpeg",
    }

    @classmethod
    def _get_content_type(cls, filename: str) -> str:
        ext = "." + filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
        return cls.CONTENT_TYPES.get(ext, "application/octet-stream")

    @classmethod
    def _generate_path(cls, folder: str, original_name: str) -> str:
        ext = "." + original_name.rsplit(".", 1)[-1].lower() if "." in original_name else ".jpg"
        unique = uuid.uuid4().hex[:12]
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        return f"{folder}/{timestamp}_{unique}{ext}"

    @classmethod
    def _get_public_url(cls, path: str) -> str:
        return f"{cls.SUPABASE_URL}/storage/v1/object/public/{cls.BUCKET}/{path}"

    @classmethod
    async def upload_file(
        cls,
        file_data: bytes,
        original_filename: str,
        folder: str = "posts",
    ) -> str:
        """
        Upload a file to Supabase Storage and return the public URL.

        Args:
            file_data: Raw file bytes
            original_filename: Original file name (for extension)
            folder: Folder path (posts, profiles, stories, reels, communities, events)

        Returns:
            Public URL of the uploaded file
        """
        file_path = cls._generate_path(folder, original_filename)
        content_type = cls._get_content_type(original_filename)

        url = f"{cls.SUPABASE_URL}/storage/v1/object/{cls.BUCKET}/{file_path}"

        headers = {
            "Authorization": f"Bearer {cls.SERVICE_KEY}",
            "apikey": settings.SUPABASE_ANON_KEY,
            "Content-Type": content_type,
            "x-upsert": "true",
        }

        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(url, content=file_data, headers=headers)

            if response.status_code not in (200, 201):
                raise Exception(
                    f"Supabase upload failed ({response.status_code}): {response.text}"
                )

        return cls._get_public_url(file_path)

    @classmethod
    async def delete_file(cls, file_url: str) -> bool:
        """Delete a file from Supabase Storage by its public URL."""
        try:
            prefix = f"{cls.SUPABASE_URL}/storage/v1/object/public/{cls.BUCKET}/"
            if not file_url.startswith(prefix):
                return False

            file_path = file_url[len(prefix):]

            url = f"{cls.SUPABASE_URL}/storage/v1/object/{cls.BUCKET}/{file_path}"
            headers = {
                "Authorization": f"Bearer {cls.SERVICE_KEY}",
                "apikey": settings.SUPABASE_ANON_KEY,
            }

            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.delete(url, headers=headers)
                return response.status_code in (200, 204)
        except Exception:
            return False


# Singleton
storage = SupabaseStorage()
