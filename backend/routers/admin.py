from fastapi import APIRouter, Depends, HTTPException, status, Request
from typing import List
from datetime import datetime, date, timezone

from schemas.community import (
    CommunityResponse, CommunityUpdate, CommunityMemberResponse,
    CommunityEventBookingResponse, SubGroupCreate, SubGroupResponse,
)
from services.auth import get_current_user


def _serialize_value(v):
    """Convert non-JSON-serializable values."""
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    return v

router = APIRouter(prefix="/api/partner", tags=["partner"])


async def require_partner(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    if current_user.get("role") != "partner":
        raise HTTPException(status_code=403, detail="Partner access required")
    return current_user


@router.get("/dashboard")
async def dashboard(
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    total_members = await pool.fetchval(
        """SELECT COUNT(DISTINCT cm.user_id)
           FROM community_members cm
           JOIN communities c ON cm.community_id = c.id
           WHERE c.created_by = $1 AND cm.status = 'active'""",
        user_id
    )

    total_payments = await pool.fetchval(
        """SELECT COALESCE(SUM(ceb.amount), 0)
           FROM community_event_bookings ceb
           JOIN community_events ce ON ceb.event_id = ce.id
           JOIN communities c ON ce.community_id = c.id
           WHERE c.created_by = $1 AND ceb.payment_status = 'confirmed'""",
        user_id
    )

    communities_count = await pool.fetchval(
        "SELECT COUNT(*) FROM communities WHERE created_by = $1",
        user_id
    )

    total_events = await pool.fetchval(
        """SELECT COUNT(*)
           FROM community_events ce
           JOIN communities c ON ce.community_id = c.id
           WHERE c.created_by = $1""",
        user_id
    )

    total_enrollments = await pool.fetchval(
        """SELECT COUNT(*)
           FROM community_event_bookings ceb
           JOIN community_events ce ON ceb.event_id = ce.id
           JOIN communities c ON ce.community_id = c.id
           WHERE c.created_by = $1""",
        user_id
    )

    recent_enrollments_rows = await pool.fetch(
        """SELECT ceb.id, ceb.amount, ceb.payment_status, ceb.created_at,
                  u.name AS user_name, u.profile_image_url AS user_profile_image,
                  ce.title AS event_title
           FROM community_event_bookings ceb
           JOIN community_events ce ON ceb.event_id = ce.id
           JOIN communities c ON ce.community_id = c.id
           JOIN users u ON ceb.user_id = u.id
           WHERE c.created_by = $1
           ORDER BY ceb.created_at DESC
           LIMIT 10""",
        user_id
    )

    recent_enrollments = [
        {
            "id": str(row["id"]),
            "user_name": row["user_name"],
            "user_profile_image": row["user_profile_image"],
            "event_title": row["event_title"],
            "amount": float(row["amount"] or 0),
            "payment_status": row["payment_status"],
            "created_at": row["created_at"].isoformat() if row["created_at"] else None,
        }
        for row in recent_enrollments_rows
    ]

    # Upcoming events across all partner's communities
    upcoming_events_rows = await pool.fetch(
        """SELECT ce.id, ce.title, ce.date, ce.location, ce.price, ce.slots, ce.image_url,
                  ce.community_id,
                  c.name AS community_name,
                  (SELECT COUNT(*) FROM community_event_bookings WHERE event_id = ce.id) AS enrolled_count
           FROM community_events ce
           JOIN communities c ON ce.community_id = c.id
           WHERE c.created_by = $1 AND ce.date >= NOW()
           ORDER BY ce.date ASC
           LIMIT 10""",
        user_id
    )

    upcoming_events = [
        {
            "id": str(row["id"]),
            "title": row["title"],
            "date": row["date"].isoformat() if row["date"] else None,
            "location": row["location"],
            "price": float(row["price"] or 0),
            "slots": row["slots"],
            "image_url": row["image_url"],
            "community_id": str(row["community_id"]),
            "community_name": row["community_name"],
            "enrolled_count": row["enrolled_count"],
        }
        for row in upcoming_events_rows
    ]

    return {
        "total_members": total_members or 0,
        "total_payments": float(total_payments or 0),
        "communities_count": communities_count or 0,
        "total_events": total_events or 0,
        "total_enrollments": total_enrollments or 0,
        "recent_enrollments": recent_enrollments,
        "upcoming_events": upcoming_events,
    }


@router.get("/communities/{community_id}/events")
async def list_community_events_admin(
    community_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Verify ownership
    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    rows = await pool.fetch("""
        SELECT ce.*, u.name AS creator_name,
               (SELECT COUNT(*) FROM community_event_bookings WHERE event_id = ce.id) AS enrolled_count
        FROM community_events ce
        JOIN users u ON ce.created_by = u.id
        WHERE ce.community_id = $1
        ORDER BY ce.date ASC
    """, community_id)

    now = datetime.utcnow()
    return [
        {k: _serialize_value(v) for k, v in dict(row).items()}
        | {
            "id": str(row["id"]),
            "community_id": str(row["community_id"]),
            "created_by": str(row["created_by"]),
            "enrolled_count": row["enrolled_count"],
            "is_past": row["date"] < now if row["date"] else False,
        }
        for row in rows
    ]


@router.get("/communities/{community_id}/events/{event_id}/enrollments")
async def get_event_enrollments_admin(
    community_id: str,
    event_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Verify ownership
    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    # Get event info
    event_row = await pool.fetchrow(
        "SELECT * FROM community_events WHERE id = $1 AND community_id = $2",
        event_id, community_id
    )
    if not event_row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    rows = await pool.fetch("""
        SELECT ceb.id, ceb.user_id, ceb.payment_status, ceb.amount, ceb.created_at AS booked_at,
               u.name AS user_name, u.profile_image_url AS user_profile_image
        FROM community_event_bookings ceb
        JOIN users u ON ceb.user_id = u.id
        WHERE ceb.event_id = $1
        ORDER BY ceb.created_at ASC
    """, event_id)

    enrolled_count = len(rows)

    event_data = {
        "id": str(event_row["id"]),
        "community_id": str(event_row["community_id"]),
        "title": event_row["title"],
        "description": event_row["description"],
        "location": event_row["location"],
        "date": event_row["date"].isoformat() if event_row["date"] else None,
        "price": float(event_row["price"] or 0),
        "slots": event_row["slots"],
        "image_url": event_row["image_url"],
        "enrolled_count": enrolled_count,
    }

    enrollments = [
        {
            "id": str(row["id"]),
            "user_id": str(row["user_id"]),
            "user_name": row["user_name"],
            "user_profile_image": row["user_profile_image"],
            "payment_status": row["payment_status"],
            "amount": float(row["amount"] or 0),
            "booked_at": row["booked_at"].isoformat() if row["booked_at"] else None,
        }
        for row in rows
    ]

    return {
        "event": event_data,
        "enrollments": enrollments,
    }


@router.get("/communities", response_model=List[CommunityResponse])
async def admin_communities(
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """SELECT c.*, u.name AS creator_name
           FROM communities c
           JOIN users u ON c.created_by = u.id
           WHERE c.created_by = $1
           ORDER BY c.created_at DESC""",
        user_id
    )

    return [
        CommunityResponse(
            id=str(row["id"]),
            name=row["name"],
            description=row["description"],
            image_url=row["image_url"],
            category=row["category"],
            is_private=row["is_private"],
            created_by=str(row["created_by"]),
            creator_name=row["creator_name"],
            members_count=row["members_count"],
            is_member=True,
            member_role="admin",
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.get("/communities/{community_id}/members", response_model=List[CommunityMemberResponse])
async def admin_community_members(
    community_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Verify ownership
    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    rows = await pool.fetch(
        """SELECT cm.*, u.name AS user_name, u.email AS user_email, u.profile_image_url AS user_profile_image
           FROM community_members cm
           JOIN users u ON cm.user_id = u.id
           WHERE cm.community_id = $1
           ORDER BY cm.joined_at ASC""",
        community_id
    )

    return [
        CommunityMemberResponse(
            id=str(row["id"]),
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            user_email=row["user_email"],
            user_profile_image=row.get("user_profile_image"),
            role=row["role"],
            status=row["status"],
            joined_at=row["joined_at"],
        )
        for row in rows
    ]


@router.get("/communities/{community_id}/payments", response_model=List[CommunityEventBookingResponse])
async def admin_community_payments(
    community_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Verify ownership
    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    rows = await pool.fetch(
        """SELECT ceb.*, u.name AS user_name
           FROM community_event_bookings ceb
           JOIN community_events ce ON ceb.event_id = ce.id
           JOIN users u ON ceb.user_id = u.id
           WHERE ce.community_id = $1
           ORDER BY ceb.created_at DESC""",
        community_id
    )

    return [
        CommunityEventBookingResponse(
            id=str(row["id"]),
            event_id=str(row["event_id"]),
            user_id=str(row["user_id"]),
            user_name=row["user_name"],
            payment_status=row["payment_status"],
            payment_id=row["payment_id"],
            amount=row["amount"],
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.put("/communities/{community_id}", response_model=CommunityResponse)
async def admin_update_community(
    community_id: str,
    data: CommunityUpdate,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Verify ownership
    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    updates = []
    params = []
    idx = 1
    for field in ["name", "description", "image_url", "category", "is_private"]:
        value = getattr(data, field)
        if value is not None:
            updates.append(f"{field} = ${idx}")
            params.append(value)
            idx += 1

    if not updates:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No fields to update")

    params.append(community_id)
    query = f"UPDATE communities SET {', '.join(updates)} WHERE id = ${idx} RETURNING *"

    row = await pool.fetchrow(query, *params)

    return CommunityResponse(
        id=str(row["id"]),
        name=row["name"],
        description=row["description"],
        image_url=row["image_url"],
        category=row["category"],
        is_private=row["is_private"],
        created_by=str(row["created_by"]),
        creator_name=current_user["name"],
        members_count=row["members_count"],
        is_member=True,
        member_role="admin",
        created_at=row["created_at"],
    )


@router.delete("/communities/{community_id}", status_code=status.HTTP_200_OK)
async def admin_delete_community(
    community_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    result = await pool.execute(
        "DELETE FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    return {"detail": "Community deleted successfully"}


@router.put("/communities/{community_id}/groups/{group_id}", response_model=SubGroupResponse)
async def admin_update_sub_group(
    community_id: str,
    group_id: str,
    data: SubGroupCreate,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Verify ownership
    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    row = await pool.fetchrow(
        """UPDATE sub_groups SET name = $1, description = $2, type = $3
           WHERE id = $4 AND community_id = $5 RETURNING *""",
        data.name, data.description, data.type, group_id, community_id
    )

    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sub-group not found")

    members_count = await pool.fetchval(
        "SELECT COUNT(*) FROM sub_group_members WHERE sub_group_id = $1", group_id
    )

    creator = await pool.fetchrow("SELECT name FROM users WHERE id = $1", str(row["created_by"]))

    return SubGroupResponse(
        id=str(row["id"]),
        community_id=str(row["community_id"]),
        name=row["name"],
        description=row["description"],
        type=row["type"],
        is_private=row.get("is_private", False) or False,
        created_by=str(row["created_by"]),
        creator_name=creator["name"] if creator else None,
        members_count=members_count or 0,
        is_member=True,
        created_at=row["created_at"],
    )


@router.delete("/communities/{community_id}/groups/{group_id}", status_code=status.HTTP_200_OK)
async def admin_delete_sub_group(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Verify ownership
    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    result = await pool.execute(
        "DELETE FROM sub_groups WHERE id = $1 AND community_id = $2",
        group_id, community_id
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sub-group not found")

    return {"detail": "Sub-group deleted successfully"}


@router.delete("/communities/{community_id}/members/{member_user_id}", status_code=status.HTTP_200_OK)
async def admin_kick_member(
    community_id: str,
    member_user_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    # Verify ownership
    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    if member_user_id == user_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot kick yourself")

    result = await pool.execute(
        "DELETE FROM community_members WHERE community_id = $1 AND user_id = $2",
        community_id, member_user_id
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Member not found")

    await pool.execute(
        "UPDATE communities SET members_count = GREATEST(members_count - 1, 0) WHERE id = $1",
        community_id
    )

    return {"detail": "Member removed successfully"}


@router.post("/communities/{community_id}/events/{event_id}/reopen")
async def admin_reopen_event(
    community_id: str,
    event_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    """Reopen a past event with a new date."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found")

    # Get request body
    body = await request.json()
    new_date = body.get("date")
    new_end_date = body.get("end_date")
    new_slots = body.get("slots")

    if not new_date:
        raise HTTPException(status_code=400, detail="New date is required")

    from datetime import datetime as dt
    try:
        parsed_date = dt.fromisoformat(new_date.replace('Z', '+00:00')).replace(tzinfo=None)
        parsed_end_date = None
        if new_end_date:
            parsed_end_date = dt.fromisoformat(new_end_date.replace('Z', '+00:00')).replace(tzinfo=None)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid date format")

    set_parts = ["date = $1"]
    params = [parsed_date]
    idx = 2

    if parsed_end_date:
        set_parts.append(f"end_date = ${idx}")
        params.append(parsed_end_date)
        idx += 1

    if new_slots:
        set_parts.append(f"slots = ${idx}")
        params.append(int(new_slots))
        idx += 1

    params.append(event_id)
    query = f"UPDATE community_events SET {', '.join(set_parts)} WHERE id = ${idx} RETURNING id, title"
    row = await pool.fetchrow(query, *params)

    if not row:
        raise HTTPException(status_code=404, detail="Event not found")

    # Clear old bookings for the reopened event
    # (optional — keep if you want to retain enrollments)

    return {"detail": "Event reopened", "id": str(row["id"]), "title": row["title"]}


@router.get("/payments")
async def admin_all_payments(
    request: Request,
    current_user: dict = Depends(require_partner),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """SELECT ceb.*, u.name AS user_name, ce.title AS event_title,
                  c.name AS community_name
           FROM community_event_bookings ceb
           JOIN community_events ce ON ceb.event_id = ce.id
           JOIN communities c ON ce.community_id = c.id
           JOIN users u ON ceb.user_id = u.id
           WHERE c.created_by = $1
           ORDER BY ceb.created_at DESC""",
        user_id
    )

    return [
        {
            "id": str(row["id"]),
            "event_id": str(row["event_id"]),
            "user_id": str(row["user_id"]),
            "user_name": row["user_name"],
            "event_title": row["event_title"],
            "community_name": row["community_name"],
            "payment_status": row["payment_status"],
            "payment_id": row["payment_id"],
            "amount": float(row["amount"] or 0),
            "created_at": row["created_at"].isoformat() if row["created_at"] else None,
        }
        for row in rows
    ]


@router.put("/communities/{community_id}/groups/{group_id}/toggle-private")
async def admin_toggle_group_private(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    """Toggle a sub-group between private and public."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    row = await pool.fetchrow(
        "UPDATE sub_groups SET is_private = NOT COALESCE(is_private, false) WHERE id = $1 AND community_id = $2 RETURNING id, is_private",
        group_id, community_id
    )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sub-group not found")

    return {"id": str(row["id"]), "is_private": row["is_private"]}


@router.get("/communities/{community_id}/groups/{group_id}/pending-requests")
async def admin_get_pending_requests(
    community_id: str,
    group_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    """Get pending join requests for a private sub-group."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    rows = await pool.fetch(
        """SELECT sgm.id, sgm.user_id, sgm.joined_at,
                  u.name AS user_name, u.profile_image_url AS user_profile_image
           FROM sub_group_members sgm
           JOIN users u ON sgm.user_id = u.id
           WHERE sgm.sub_group_id = $1 AND sgm.status = 'pending'
           ORDER BY sgm.joined_at ASC""",
        group_id
    )

    return [
        {
            "id": str(row["id"]),
            "user_id": str(row["user_id"]),
            "user_name": row["user_name"],
            "user_profile_image": row.get("user_profile_image"),
            "requested_at": row["joined_at"].isoformat() if row["joined_at"] else None,
        }
        for row in rows
    ]


@router.post("/communities/{community_id}/groups/{group_id}/approve-request/{member_user_id}")
async def admin_approve_join_request(
    community_id: str,
    group_id: str,
    member_user_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    """Approve a pending join request for a sub-group."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    result = await pool.execute(
        "UPDATE sub_group_members SET status = 'active' WHERE sub_group_id = $1 AND user_id = $2 AND status = 'pending'",
        group_id, member_user_id
    )

    if result == "UPDATE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No pending request found")

    return {"detail": "Join request approved"}


@router.post("/communities/{community_id}/groups/{group_id}/reject-request/{member_user_id}")
async def admin_reject_join_request(
    community_id: str,
    group_id: str,
    member_user_id: str,
    request: Request,
    current_user: dict = Depends(require_partner),
):
    """Reject a pending join request for a sub-group."""
    pool = request.app.state.pool
    user_id = current_user["id"]

    community = await pool.fetchrow(
        "SELECT id FROM communities WHERE id = $1 AND created_by = $2",
        community_id, user_id
    )
    if not community:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found or not owned by you")

    result = await pool.execute(
        "DELETE FROM sub_group_members WHERE sub_group_id = $1 AND user_id = $2 AND status = 'pending'",
        group_id, member_user_id
    )

    if result == "DELETE 0":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No pending request found")

    return {"detail": "Join request rejected"}
