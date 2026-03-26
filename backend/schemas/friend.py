from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class FriendRequestCreate(BaseModel):
    addressee_id: str


class FriendRequestResponse(BaseModel):
    id: str
    requester_id: str
    addressee_id: str
    status: str
    requester_name: Optional[str] = None
    requester_image: Optional[str] = None
    addressee_name: Optional[str] = None
    addressee_image: Optional[str] = None
    created_at: datetime


class FriendResponse(BaseModel):
    id: str
    name: str
    email: str
    bio: Optional[str] = ""
    profile_image_url: Optional[str] = None
    interests: list = []


class FriendshipStatus(BaseModel):
    status: str  # 'none', 'pending_sent', 'pending_received', 'friends'
    request_id: Optional[str] = None
