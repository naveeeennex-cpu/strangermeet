from pydantic import BaseModel, EmailStr, Field
from typing import List, Optional
from datetime import datetime


class UserSignup(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    email: EmailStr
    password: str = Field(..., min_length=6)
    phone: str = ""
    interests: List[str] = []
    role: str = "customer"


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserResponse(BaseModel):
    id: str
    name: str
    email: str
    bio: Optional[str] = ""
    phone: str = ""
    interests: List[str] = []
    profile_image_url: Optional[str] = None
    cover_image_url: Optional[str] = None
    role: str = "customer"
    created_at: datetime


class UserUpdate(BaseModel):
    bio: Optional[str] = None
    phone: Optional[str] = None
    interests: Optional[List[str]] = None
    profile_image_url: Optional[str] = None


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str = "customer"
