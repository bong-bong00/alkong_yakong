from typing import List
from fastapi import APIRouter

from app.models.schemas import HeartRateCreate
from app.services.biosignal_service import get_abnormal_events, save_heart_rate_bulk

router = APIRouter(prefix="/api/v1", tags=["Biosignal"])

@router.post("/biosignal/heart-rate")
def create_heart_rate(request: List[HeartRateCreate]):
    return save_heart_rate_bulk(request)

@router.get("/users/{user_id}/biosignal/events")
def list_abnormal_events(user_id: str):
    return get_abnormal_events(user_id)
