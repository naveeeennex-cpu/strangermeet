from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class MessageModel(BaseModel):
    id: Optional[str] = None
    sender_id: str
    receiver_id: str
    message: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    is_read: bool = False
