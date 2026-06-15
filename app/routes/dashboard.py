from typing import Optional

from fastapi import APIRouter, Query

from app.services.dashboard_service import get_dashboard


router = APIRouter(prefix="/api/v1", tags=["Dashboard"])


@router.get("/users/{user_id}/dashboard")
def user_dashboard(
    user_id: str,
    date: Optional[str] = Query(default=None, description="YYYY-MM-DD"),
):
    return get_dashboard(user_id, date)
