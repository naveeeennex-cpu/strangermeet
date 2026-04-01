from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class ReelCreate(BaseModel):
    media_url: str
    media_type: str = "image"
    caption: str = ""


class ReelResponse(BaseModel):
    id: str
    user_id: str
    user_name: Optional[str] = None
    user_profile_image: Optional[str] = None
    media_url: str
    media_type: str = "image"
    caption: str = ""
    likes_count: int = 0
    is_liked: bool = False
    comments_count: int = 0
    created_at: datetime


class ReelCommentCreate(BaseModel):
    text: str = Field(..., min_length=1)


class ReelCommentResponse(BaseModel):
    id: str
    reel_id: str
    user_id: str
    user_name: Optional[str] = None
    text: str
    created_at: datetime
