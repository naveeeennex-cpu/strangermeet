from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime


class PostCreate(BaseModel):
    caption: str = Field(..., min_length=1)
    image_url: Optional[str] = None


class PostResponse(BaseModel):
    id: str
    user_id: str
    user_name: Optional[str] = None
    user_profile_image: Optional[str] = None
    image_url: Optional[str] = None
    caption: str
    likes: List[str] = []
    likes_count: int = 0
    is_liked: bool = False
    comments_count: int = 0
    created_at: datetime


class PostUpdate(BaseModel):
    caption: Optional[str] = None
    image_url: Optional[str] = None


class CommentCreate(BaseModel):
    text: str = Field(..., min_length=1)


class CommentResponse(BaseModel):
    id: str
    post_id: str
    user_id: str
    user_name: Optional[str] = None
    user_profile_image: Optional[str] = None
    text: str
    likes_count: int = 0
    is_liked: bool = False
    replies_count: int = 0
    created_at: datetime
