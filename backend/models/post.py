from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class PostModel(BaseModel):
    id: Optional[str] = None
    user_id: str
    image_url: Optional[str] = None
    media_type: str = "image"
    video_url: Optional[str] = None
    caption: str
    likes_count: int = 0
    created_at: datetime = Field(default_factory=datetime.utcnow)


class CommentModel(BaseModel):
    id: Optional[str] = None
    post_id: str
    user_id: str
    text: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class PostLikeModel(BaseModel):
    id: Optional[str] = None
    post_id: str
    user_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
