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


# ── Event Memories ──────────────────────────────────────────────────────────

@router.post("/events/{event_id}/memories")
async def upload_memory(event_id: str, request: Request, current_user: dict = Depends(get_current_user)):
    pool = request.app.state.pool
    user_id = current_user["id"]
    body = await request.json()
    media_url = body.get("media_url", "")
    media_type = body.get("media_type", "image")
    caption = body.get("caption", "")
    if not media_url:
        raise HTTPException(400, "media_url required")
    # Verify: user must have booked OR be community admin
    booking = await pool.fetchrow(
        "SELECT id FROM community_event_bookings WHERE event_id = $1 AND user_id = $2",
        event_id, user_id,
    )
    if not booking:
        admin = await pool.fetchrow(
            "SELECT c.created_by FROM community_events ce JOIN communities c ON ce.community_id = c.id WHERE ce.id = $1 AND c.created_by = $2",
            event_id, user_id,
        )
        if not admin:
            raise HTTPException(403, "Only attendees and admin can upload")
    row = await pool.fetchrow(
        "INSERT INTO event_memories (event_id, user_id, media_url, media_type, caption) VALUES ($1,$2,$3,$4,$5) RETURNING *",
        event_id, user_id, media_url, media_type, caption,
    )
    return {
        "id": str(row["id"]),
        "event_id": str(row["event_id"]),
        "user_id": user_id,
        "user_name": current_user["name"],
        "user_profile_image": current_user.get("profile_image_url"),
        "media_url": row["media_url"],
        "media_type": row["media_type"],
        "caption": row["caption"] or "",
        "created_at": row["created_at"].isoformat(),
    }


@router.get("/events/{event_id}/memories")
async def get_memories(event_id: str, request: Request, current_user: dict = Depends(get_current_user)):
    pool = request.app.state.pool
    rows = await pool.fetch(
        """SELECT em.*, u.name AS user_name, u.profile_image_url AS user_profile_image
           FROM event_memories em
           JOIN users u ON em.user_id = u.id
           WHERE em.event_id = $1
           ORDER BY em.created_at DESC""",
        event_id,
    )
    return [
        {
            "id": str(r["id"]),
            "event_id": str(r["event_id"]),
            "user_id": str(r["user_id"]),
            "user_name": r["user_name"],
            "user_profile_image": r.get("user_profile_image"),
            "media_url": r["media_url"],
            "media_type": r["media_type"] or "image",
            "caption": r["caption"] or "",
            "created_at": r["created_at"].isoformat(),
        }
        for r in rows
    ]


@router.delete("/events/{event_id}/memories/{memory_id}")
async def delete_memory(event_id: str, memory_id: str, request: Request, current_user: dict = Depends(get_current_user)):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Check if user is community admin
    is_admin = False
    admin_check = await pool.fetchrow(
        """SELECT c.created_by FROM community_events ce
           JOIN communities c ON ce.community_id = c.id
           WHERE ce.id = $1 AND c.created_by = $2""",
        event_id, user_id,
    )
    if admin_check:
        is_admin = True

    if is_admin:
        # Admin can delete any memory
        result = await pool.execute("DELETE FROM event_memories WHERE id = $1", memory_id)
    else:
        # Regular user can only delete their own
        result = await pool.execute(
            "DELETE FROM event_memories WHERE id = $1 AND user_id = $2",
            memory_id, user_id,
        )

    if result == "DELETE 0":
        raise HTTPException(404, "Not found or not authorized")
    return {"detail": "Deleted"}


# ── Saved / Bookmark ───────────────────────────────────────────────────────


@router.post("/saved")
async def save_item(request: Request, current_user: dict = Depends(get_current_user)):
    """Save (bookmark) a post, trip, or event."""
    pool = request.app.state.pool
    body = await request.json()
    item_id = body.get("item_id")
    item_type = body.get("item_type")  # 'post', 'trip', 'event'
    if not item_id or not item_type:
        raise HTTPException(400, "item_id and item_type required")
    try:
        await pool.execute(
            "INSERT INTO saved_items (user_id, item_id, item_type) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
            current_user["id"], item_id, item_type,
        )
    except Exception:
        pass
    return {"detail": "Saved"}


@router.delete("/saved/{item_id}")
async def unsave_item(item_id: str, request: Request, current_user: dict = Depends(get_current_user)):
    """Remove a saved item."""
    pool = request.app.state.pool
    await pool.execute(
        "DELETE FROM saved_items WHERE user_id = $1 AND item_id = $2",
        current_user["id"], item_id,
    )
    return {"detail": "Unsaved"}


@router.get("/saved/check/{item_id}")
async def check_saved(item_id: str, request: Request, current_user: dict = Depends(get_current_user)):
    """Check whether a specific item is saved."""
    pool = request.app.state.pool
    row = await pool.fetchrow(
        "SELECT id FROM saved_items WHERE user_id = $1 AND item_id = $2",
        current_user["id"], item_id,
    )
    return {"is_saved": row is not None}


@router.get("/saved")
async def get_saved_items(request: Request, item_type: str = "", current_user: dict = Depends(get_current_user)):
    """Return all saved items for the current user, optionally filtered by type."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    if item_type and item_type != "all":
        rows = await pool.fetch(
            "SELECT * FROM saved_items WHERE user_id = $1 AND item_type = $2 ORDER BY created_at DESC",
            user_id, item_type,
        )
    else:
        rows = await pool.fetch(
            "SELECT * FROM saved_items WHERE user_id = $1 ORDER BY created_at DESC",
            user_id,
        )

    results = []
    for row in rows:
        item = {
            "id": str(row["id"]),
            "item_id": row["item_id"],
            "item_type": row["item_type"],
            "saved_at": row["created_at"].isoformat(),
            "details": None,
        }

        try:
            if row["item_type"] == "post":
                post = await pool.fetchrow(
                    "SELECT p.*, u.name AS user_name, u.profile_image_url AS user_profile_image FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = $1",
                    row["item_id"],
                )
                if post:
                    item["details"] = {
                        "id": str(post["id"]),
                        "caption": post["caption"],
                        "image_url": post["image_url"],
                        "user_name": post["user_name"],
                        "user_profile_image": post.get("user_profile_image"),
                        "media_type": post.get("media_type", "image"),
                        "likes_count": post.get("likes_count", 0),
                    }
            elif row["item_type"] in ("trip", "event"):
                event = await pool.fetchrow(
                    """SELECT ce.*, c.name AS community_name, c.image_url AS community_image
                       FROM community_events ce
                       JOIN communities c ON ce.community_id = c.id
                       WHERE ce.id = $1""",
                    row["item_id"],
                )
                if event:
                    item["details"] = {
                        "id": str(event["id"]),
                        "community_id": str(event["community_id"]),
                        "title": event["title"],
                        "location": event["location"],
                        "date": event["date"].isoformat() if event["date"] else None,
                        "price": float(event["price"] or 0),
                        "image_url": event["image_url"],
                        "event_type": event.get("event_type", "event"),
                        "community_name": event["community_name"],
                        "community_image": event.get("community_image"),
                        "slots": event["slots"],
                        "difficulty": event.get("difficulty", "easy"),
                        "duration_days": event.get("duration_days", 1),
                    }
        except Exception:
            pass

        if item["details"] is not None:
            results.append(item)

    return results


@router.get("/events/{event_id}/memories/count")
async def get_memories_count(event_id: str, request: Request, current_user: dict = Depends(get_current_user)):
    pool = request.app.state.pool
    count = await pool.fetchval(
        "SELECT COUNT(*) FROM event_memories WHERE event_id = $1",
        event_id,
    )
    return {"count": count or 0}
