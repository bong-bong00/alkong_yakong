from typing import Optional

from fastapi import APIRouter, Query

from app.services.dashboard_service import get_dashboard
from app.models.response_schemas import DashboardResponse


router = APIRouter(prefix="/api/v1", tags=["Dashboard"])


@router.get("/users/{user_id}/dashboard", response_model=DashboardResponse)
def user_dashboard(
    user_id: str,
    date: Optional[str] = Query(default=None, description="YYYY-MM-DD"),
):
    return get_dashboard(user_id, date)
