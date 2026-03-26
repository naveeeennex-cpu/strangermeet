from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class EventModel(BaseModel):
    id: Optional[str] = None
    title: str
    description: str
    location: str
    date: datetime
    price: float = 0.0
    slots: int
    image_url: Optional[str] = None
    created_by: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class BookingModel(BaseModel):
    id: Optional[str] = None
    user_id: str
    event_id: str
    payment_status: str = "pending"
    payment_id: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
