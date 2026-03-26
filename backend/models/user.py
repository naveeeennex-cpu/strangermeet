from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime


class UserModel(BaseModel):
    id: Optional[str] = None
    name: str
    email: str
    password_hash: str
    bio: Optional[str] = ""
    interests: List[str] = []
    profile_image_url: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
