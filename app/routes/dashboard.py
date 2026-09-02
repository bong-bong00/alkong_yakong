from typing import Optional

from fastapi import APIRouter, Query

from app.services.dashboard_service import get_dashboard
from app.services.today_medication_service import get_today_medicines


router = APIRouter(prefix="/api/v1", tags=["Dashboard"])


@router.get("/users/{user_id}/dashboard")
def user_dashboard(
    user_id: str,
    date: Optional[str] = Query(default=None, description="YYYY-MM-DD"),
):
    return get_dashboard(user_id, date)


@router.get("/users/{user_id}/today-medicines")
def user_today_medicines(
    user_id: str,
    date: Optional[str] = Query(default=None, description="YYYY-MM-DD"),
):
    """오늘 홈에 보여줄 복약 목록 (user_medicines 기반)."""
    return get_today_medicines(user_id, date)
