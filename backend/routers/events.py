from fastapi import APIRouter, Depends, HTTPException, status, Query, Request
from typing import List
import uuid

from schemas.event import EventCreate, EventResponse, BookingResponse
from services.auth import get_current_user

router = APIRouter(prefix="/api/events", tags=["events"])


def _row_to_event_response(row) -> EventResponse:
    return EventResponse(
        id=str(row["id"]),
        title=row["title"],
        description=row["description"] or "",
        location=row["location"] or "",
        date=row["date"],
        price=row["price"] or 0.0,
        slots=row["slots"] or 0,
        image_url=row["image_url"] or None,
        created_by=str(row["created_by"]),
        creator_name=row.get("creator_name") or "Unknown",
        participants=list(row["participants"]) if row.get("participants") else [],
        participants_count=row.get("participants_count", 0),
        created_at=row["created_at"],
    )


@router.post("", response_model=EventResponse, status_code=status.HTTP_201_CREATED)
async def create_event(
    event_data: EventCreate,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    try:
        row = await pool.fetchrow(
            """
            INSERT INTO events (title, description, location, date, price, slots, image_url, created_by)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING *
            """,
            event_data.title,
            event_data.description,
            event_data.location,
            event_data.date,
            event_data.price,
            event_data.slots,
            event_data.image_url or "",
            user_id,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create event: {str(e)}",
        )

    return EventResponse(
        id=str(row["id"]),
        title=row["title"],
        description=row["description"] or "",
        location=row["location"] or "",
        date=row["date"],
        price=row["price"] or 0.0,
        slots=row["slots"] or 0,
        image_url=row["image_url"] or None,
        created_by=str(row["created_by"]),
        creator_name=current_user["name"],
        participants=[],
        participants_count=0,
        created_at=row["created_at"],
    )


@router.get("", response_model=List[EventResponse])
async def list_events(
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    rows = await pool.fetch(
        """
        SELECT e.*,
               u.name AS creator_name,
               (SELECT COUNT(*) FROM bookings b WHERE b.event_id = e.id) AS participants_count,
               ARRAY(SELECT b2.user_id::text FROM bookings b2 WHERE b2.event_id = e.id) AS participants
        FROM events e
        JOIN users u ON e.created_by = u.id
        ORDER BY e.date ASC
        OFFSET $1 LIMIT $2
        """,
        skip,
        limit,
    )

    return [_row_to_event_response(row) for row in rows]


@router.get("/{event_id}", response_model=EventResponse)
async def get_event(
    event_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool

    try:
        row = await pool.fetchrow(
            """
            SELECT e.*,
                   u.name AS creator_name,
                   (SELECT COUNT(*) FROM bookings b WHERE b.event_id = e.id) AS participants_count,
                   ARRAY(SELECT b2.user_id::text FROM bookings b2 WHERE b2.event_id = e.id) AS participants
            FROM events e
            JOIN users u ON e.created_by = u.id
            WHERE e.id = $1
            """,
            event_id,
        )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid event ID format",
        )

    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    return _row_to_event_response(row)


@router.post("/{event_id}/join", response_model=BookingResponse)
async def join_event(
    event_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Check event exists
    try:
        event = await pool.fetchrow("SELECT * FROM events WHERE id = $1", event_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid event ID format",
        )

    if not event:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    # Check if already joined
    existing_booking = await pool.fetchrow(
        "SELECT id FROM bookings WHERE user_id = $1 AND event_id = $2",
        user_id,
        event_id,
    )

    if existing_booking:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You have already joined this event",
        )

    # Check slot availability
    booking_count = await pool.fetchval(
        "SELECT COUNT(*) FROM bookings WHERE event_id = $1",
        event_id,
    )

    if booking_count >= event["slots"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event is fully booked",
        )

    mock_payment_id = f"mock_pay_{uuid.uuid4().hex[:12]}"

    try:
        row = await pool.fetchrow(
            """
            INSERT INTO bookings (user_id, event_id, payment_status, payment_id)
            VALUES ($1, $2, $3, $4)
            RETURNING *
            """,
            user_id,
            event_id,
            "completed",
            mock_payment_id,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create booking: {str(e)}",
        )

    return BookingResponse(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        event_id=str(row["event_id"]),
        payment_status=row["payment_status"],
        payment_id=row["payment_id"],
        created_at=row["created_at"],
    )
