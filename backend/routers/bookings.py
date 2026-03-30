from fastapi import APIRouter, Depends, HTTPException, Request
from services.auth import get_current_user

router = APIRouter(prefix="/api/bookings", tags=["bookings"])


# ── Reviews ──────────────────────────────────────────────────────────────────

@router.post("/events/{event_id}/review")
async def create_review(
    event_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Submit a rating and review for a past event."""
    pool = request.app.state.pool
    user_id = current_user["id"]
    body = await request.json()

    rating = body.get("rating")
    review_text = body.get("review", "")
    images = body.get("images", [])

    if not rating or not (1 <= rating <= 5):
        raise HTTPException(status_code=400, detail="Rating must be between 1 and 5")

    # Check if user booked this event
    booking = await pool.fetchrow(
        "SELECT id FROM community_event_bookings WHERE event_id = $1 AND user_id = $2",
        event_id, user_id,
    )
    if not booking:
        raise HTTPException(status_code=403, detail="You can only review events you attended")

    # Check if already reviewed
    existing = await pool.fetchrow(
        "SELECT id FROM event_reviews WHERE event_id = $1 AND user_id = $2",
        event_id, user_id,
    )
    if existing:
        # Update existing review
        row = await pool.fetchrow(
            "UPDATE event_reviews SET rating = $1, review = $2, images = $3 WHERE event_id = $4 AND user_id = $5 RETURNING *",
            rating, review_text, images, event_id, user_id,
        )
    else:
        row = await pool.fetchrow(
            "INSERT INTO event_reviews (event_id, user_id, rating, review, images) VALUES ($1, $2, $3, $4, $5) RETURNING *",
            event_id, user_id, rating, review_text, images,
        )

    return {
        "id": str(row["id"]),
        "event_id": str(row["event_id"]),
        "user_id": str(row["user_id"]),
        "user_name": current_user["name"],
        "user_profile_image": current_user.get("profile_image_url"),
        "rating": row["rating"],
        "review": row["review"],
        "images": list(row["images"] or []),
        "created_at": row["created_at"].isoformat(),
    }


@router.get("/events/{event_id}/reviews")
async def get_event_reviews(
    event_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Get all reviews for an event."""
    pool = request.app.state.pool

    rows = await pool.fetch(
        """SELECT er.*, u.name AS user_name, u.profile_image_url AS user_profile_image
           FROM event_reviews er
           JOIN users u ON er.user_id = u.id
           WHERE er.event_id = $1
           ORDER BY er.created_at DESC""",
        event_id,
    )

    avg_rating = await pool.fetchval(
        "SELECT AVG(rating)::float FROM event_reviews WHERE event_id = $1",
        event_id,
    )

    reviews = [
        {
            "id": str(row["id"]),
            "event_id": str(row["event_id"]),
            "user_id": str(row["user_id"]),
            "user_name": row["user_name"],
            "user_profile_image": row.get("user_profile_image"),
            "rating": row["rating"],
            "review": row["review"] or "",
            "images": list(row["images"] or []),
            "created_at": row["created_at"].isoformat(),
        }
        for row in rows
    ]

    return {
        "reviews": reviews,
        "average_rating": round(avg_rating or 0, 1),
        "total_reviews": len(reviews),
    }


@router.get("/my")
async def get_my_bookings(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    """Get all bookings for the current user — both community events and standalone events."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Community event bookings
    community_bookings = await pool.fetch(
        """SELECT ceb.id, ceb.event_id, ceb.payment_status, ceb.amount, ceb.created_at AS booked_at,
                  ce.title AS event_title, ce.description, ce.location, ce.date AS event_date,
                  ce.end_date, ce.price, ce.slots, ce.image_url AS event_image,
                  ce.event_type, ce.duration_days, ce.difficulty,
                  ce.community_id,
                  c.name AS community_name, c.image_url AS community_image
           FROM community_event_bookings ceb
           JOIN community_events ce ON ceb.event_id = ce.id
           JOIN communities c ON ce.community_id = c.id
           WHERE ceb.user_id = $1
           ORDER BY ce.date DESC""",
        user_id,
    )

    results = []
    for row in community_bookings:
        results.append({
            "id": str(row["id"]),
            "event_id": str(row["event_id"]),
            "community_id": str(row["community_id"]),
            "event_title": row["event_title"],
            "description": row["description"] or "",
            "location": row["location"] or "",
            "event_date": row["event_date"].isoformat() if row["event_date"] else None,
            "end_date": row["end_date"].isoformat() if row["end_date"] else None,
            "price": float(row["price"] or 0),
            "amount": float(row["amount"] or 0),
            "slots": row["slots"] or 0,
            "image_url": row["event_image"] or "",
            "event_image": row["event_image"] or "",
            "event_type": row["event_type"] or "event",
            "duration_days": row["duration_days"] or 1,
            "difficulty": row["difficulty"] or "easy",
            "community_name": row["community_name"] or "",
            "community_image": row["community_image"] or "",
            "payment_status": row["payment_status"] or "confirmed",
            "booked_at": row["booked_at"].isoformat() if row["booked_at"] else None,
        })

    return results
