from pydantic import BaseModel, Field, field_validator
from typing import Optional, List
from datetime import datetime


class CommunityCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str = ""
    image_url: str = ""
    category: str = ""
    is_private: bool = False


class CommunityUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    image_url: Optional[str] = None
    category: Optional[str] = None
    is_private: Optional[bool] = None


class CommunityResponse(BaseModel):
    id: str
    name: str
    description: str = ""
    image_url: str = ""
    category: str = ""
    is_private: bool = False
    created_by: str
    creator_name: Optional[str] = None
    creator_image: Optional[str] = None
    admin_phone: Optional[str] = None
    members_count: int = 0
    is_member: bool = False
    member_role: Optional[str] = None
    created_at: datetime


class CommunityPostCreate(BaseModel):
    image_url: str = ""
    caption: str = ""


class CommunityPostResponse(BaseModel):
    id: str
    community_id: str
    user_id: str
    user_name: Optional[str] = None
    user_profile_image: Optional[str] = None
    image_url: str = ""
    caption: str = ""
    likes_count: int = 0
    is_liked: bool = False
    comments_count: int = 0
    created_at: datetime


class CommunityPostCommentCreate(BaseModel):
    text: str = Field(..., min_length=1)


class CommunityPostCommentResponse(BaseModel):
    id: str
    post_id: str
    user_id: str
    user_name: Optional[str] = None
    text: str
    created_at: datetime


class SubGroupCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str = ""
    type: str = "general"


class SubGroupResponse(BaseModel):
    id: str
    community_id: str
    name: str
    description: str = ""
    type: str = "general"
    is_private: bool = False
    admin_only_chat: bool = False
    created_by: str
    creator_name: Optional[str] = None
    members_count: int = 0
    is_member: bool = False
    member_status: Optional[str] = None
    created_at: datetime


class CommunityMessageCreate(BaseModel):
    message: str = ""
    image_url: str = ""
    message_type: str = "text"


class CommunityMessageResponse(BaseModel):
    id: str
    community_id: str
    user_id: str
    user_name: Optional[str] = None
    user_profile_image: Optional[str] = None
    message: str
    timestamp: datetime
    image_url: str = ""
    message_type: str = "text"
    is_deleted: bool = False
    deleted_by: Optional[str] = None
    is_pinned: bool = False


class SubGroupMessageCreate(BaseModel):
    message: str = ""
    image_url: str = ""
    message_type: str = "text"


class SubGroupMessageResponse(BaseModel):
    id: str
    sub_group_id: str
    user_id: str
    user_name: Optional[str] = None
    user_profile_image: Optional[str] = None
    message: str
    timestamp: datetime
    image_url: str = ""
    message_type: str = "text"
    is_deleted: bool = False
    deleted_by: Optional[str] = None
    is_pinned: bool = False


class CommunityEventCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    description: str = ""
    location: str = ""
    date: datetime
    price: float = 0
    slots: int = 0
    image_url: str = ""
    event_type: str = "event"
    duration_days: int = 1
    difficulty: str = "easy"
    includes: List[str] = []
    excludes: List[str] = []
    meeting_point: str = ""
    end_date: Optional[datetime] = None
    max_altitude_m: float = 0
    total_distance_km: float = 0

    @field_validator('date', mode='before')
    @classmethod
    def ensure_timezone_aware(cls, v):
        if isinstance(v, str):
            from dateutil import parser
            v = parser.parse(v)
        if isinstance(v, datetime) and v.tzinfo is None:
            from datetime import timezone
            v = v.replace(tzinfo=timezone.utc)
        return v


class CommunityEventResponse(BaseModel):
    id: str
    community_id: str
    title: str
    description: str = ""
    location: str = ""
    date: datetime
    price: float = 0
    slots: int = 0
    image_url: str = ""
    created_by: str
    creator_name: Optional[str] = None
    is_booked: bool = False
    is_joined: bool = False
    participants_count: int = 0
    event_type: str = "event"
    duration_days: int = 1
    difficulty: str = "easy"
    includes: List[str] = []
    excludes: List[str] = []
    meeting_point: str = ""
    end_date: Optional[datetime] = None
    max_altitude_m: float = 0
    total_distance_km: float = 0
    community_name: Optional[str] = None
    community_image: Optional[str] = None
    is_past: bool = False
    created_at: datetime


class ItineraryDayCreate(BaseModel):
    day_number: int
    title: str
    description: str = ""
    activities: List[str] = []
    meals_included: List[str] = []
    accommodation: str = ""
    distance_km: float = 0
    elevation_m: float = 0


class ItineraryDayResponse(BaseModel):
    id: str
    event_id: str
    day_number: int
    title: str
    description: str = ""
    activities: List[str] = []
    meals_included: List[str] = []
    accommodation: str = ""
    distance_km: float = 0
    elevation_m: float = 0


class CommunityEventBookingResponse(BaseModel):
    id: str
    event_id: str
    user_id: str
    user_name: Optional[str] = None
    payment_status: str = "pending"
    payment_id: str = ""
    amount: float = 0
    created_at: datetime


class EventParticipantResponse(BaseModel):
    user_id: str
    user_name: Optional[str] = None
    user_profile_image: Optional[str] = None
    booked_at: datetime


class CommunityMemberResponse(BaseModel):
    id: str
    user_id: str
    user_name: Optional[str] = None
    user_email: Optional[str] = None
    user_profile_image: Optional[str] = None
    role: str = "member"
    status: str = "active"
    joined_at: datetime


class SubGroupMemberResponse(BaseModel):
    id: str
    user_id: str
    user_name: Optional[str] = None
    user_profile_image: Optional[str] = None
    joined_at: datetime


class EventRideCreate(BaseModel):
    vehicle_type: str = "car"          # 'car' or 'bike'
    vehicle_model: str = ""
    vehicle_color: str = ""
    total_seats: int = 1
    start_location: str
    start_time: datetime
    is_free: bool = True
    cost_per_person: float = 0
    notes: str = ""

    @field_validator('start_time', mode='before')
    @classmethod
    def ensure_timezone_aware(cls, v):
        if isinstance(v, str):
            from dateutil import parser
            v = parser.parse(v)
        if isinstance(v, datetime) and v.tzinfo is None:
            from datetime import timezone
            v = v.replace(tzinfo=timezone.utc)
        return v


class EventRidePassengerResponse(BaseModel):
    id: str
    user_id: str
    user_name: Optional[str] = None
    user_profile_image: Optional[str] = None
    joined_at: datetime


class EventRideResponse(BaseModel):
    id: str
    event_id: str
    user_id: str
    driver_name: Optional[str] = None
    driver_image: Optional[str] = None
    vehicle_type: str = "car"
    vehicle_model: str = ""
    vehicle_color: str = ""
    total_seats: int = 1
    available_seats: int = 1
    start_location: str = ""
    start_time: datetime
    is_free: bool = True
    cost_per_person: float = 0
    notes: str = ""
    is_driver: bool = False
    is_passenger: bool = False
    passengers: List[EventRidePassengerResponse] = []
    created_at: datetime
