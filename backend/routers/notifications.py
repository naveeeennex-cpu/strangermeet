import json
from fastapi import APIRouter, Depends, Request, status
from typing import List
from pydantic import BaseModel
from datetime import datetime

from services.auth import get_current_user

router = APIRouter(prefix="/api/notifications", tags=["notifications"])


class NotificationResponse(BaseModel):
    id: str
    type: str
    title: str
    body: str
    data: dict = {}
    is_read: bool
    created_at: datetime


@router.get("", response_model=List[NotificationResponse])
async def get_notifications(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]

    rows = await pool.fetch(
        """SELECT * FROM notifications
           WHERE user_id = $1
           ORDER BY created_at DESC
           LIMIT 100""",
        user_id,
    )

    return [
        NotificationResponse(
            id=str(r["id"]),
            type=r["type"],
            title=r["title"],
            body=r["body"],
            data=dict(r["data"]) if r["data"] else {},
            is_read=r["is_read"],
            created_at=r["created_at"],
        )
        for r in rows
    ]


@router.post("/{notification_id}/read", status_code=status.HTTP_200_OK)
async def mark_read(
    notification_id: str,
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]
    await pool.execute(
        "UPDATE notifications SET is_read = TRUE WHERE id = $1 AND user_id = $2",
        notification_id, user_id,
    )
    return {"ok": True}


@router.post("/read-all", status_code=status.HTTP_200_OK)
async def mark_all_read(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]
    await pool.execute(
        "UPDATE notifications SET is_read = TRUE WHERE user_id = $1",
        user_id,
    )
    return {"ok": True}


@router.get("/unread-count")
async def unread_count(
    request: Request,
    current_user: dict = Depends(get_current_user),
):
    pool = request.app.state.pool
    user_id = current_user["id"]
    count = await pool.fetchval(
        "SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_read = FALSE",
        user_id,
    )
    return {"count": int(count)}
