from fastapi import APIRouter

from app.models.schemas import HeartRateCreate
from app.services.biosignal_service import get_abnormal_events, save_heart_rate


router = APIRouter(prefix="/api/v1", tags=["Biosignal"])


@router.post("/biosignal/heart-rate")
def create_heart_rate(request: HeartRateCreate):
    return save_heart_rate(request)


@router.get("/users/{user_id}/biosignal/events")
def list_abnormal_events(user_id: str):
    return get_abnormal_events(user_id)
