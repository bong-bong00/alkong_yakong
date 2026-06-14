from fastapi import APIRouter

from app.models.schemas import DurAnalyzeRequest
from app.services.dur_service import analyze_dur, get_latest_dur


router = APIRouter(prefix="/api/v1", tags=["DUR Analysis"])


@router.post("/dur/analyze")
def analyze(request: DurAnalyzeRequest):
    return analyze_dur(request)


@router.get("/users/{user_id}/dur/latest")
def latest(user_id: str):
    return get_latest_dur(user_id)
