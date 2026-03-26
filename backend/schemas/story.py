from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class StoryCreate(BaseModel):
    image_url: str
    caption: str = ""


class StoryResponse(BaseModel):
    id: str
    user_id: str
    user_name: str
    user_image: Optional[str] = None
    image_url: str
    caption: str = ""
    views_count: int = 0
    is_viewed: bool = False
    created_at: datetime
    expires_at: datetime


class UserStories(BaseModel):
    user_id: str
    user_name: str
    user_image: Optional[str] = None
    stories: List[StoryResponse] = []
    has_unviewed: bool = True


class StoryReplyCreate(BaseModel):
    message: str


class StoryReplyResponse(BaseModel):
    id: str
    story_id: str
    user_id: str
    user_name: str
    user_image: Optional[str] = None
    message: str
    created_at: datetime
