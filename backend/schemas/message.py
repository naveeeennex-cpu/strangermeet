from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class MessageCreate(BaseModel):
    receiver_id: str
    message: str = ""
    image_url: str = ""
    message_type: str = "text"


class MessageResponse(BaseModel):
    id: str
    sender_id: str
    receiver_id: str
    message: str
    timestamp: datetime
    is_read: bool = False
    status: str = "sent"  # 'sent', 'delivered', 'read'
    sender_name: Optional[str] = None
    image_url: str = ""
    message_type: str = "text"
