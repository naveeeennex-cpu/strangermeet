from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime


class EventCreate(BaseModel):
    title: str = Field(..., min_length=1)
    description: str = Field(..., min_length=1)
    location: str = Field(..., min_length=1)
    date: datetime
    price: float = 0.0
    slots: int = Field(..., gt=0)
    image_url: Optional[str] = None


class EventResponse(BaseModel):
    id: str
    title: str
    description: str
    location: str
    date: datetime
    price: float
    slots: int
    image_url: Optional[str] = None
    created_by: str
    creator_name: Optional[str] = None
    participants: List[str] = []
    participants_count: int = 0
    created_at: datetime


class BookingResponse(BaseModel):
    id: str
    user_id: str
    event_id: str
    payment_status: str
    payment_id: Optional[str] = None
    created_at: datetime
