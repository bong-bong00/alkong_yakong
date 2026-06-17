from fastapi import APIRouter

from app.models.schemas import DurAnalyzeRequest, DurSyncRequest
from app.services.dur_service import analyze_dur, get_latest_dur
from app.services.dur_sync_service import diagnose_dur_api_key, sync_mfds_dur


router = APIRouter(prefix="/api/v1", tags=["DUR Analysis"])


@router.post("/dur/analyze")
def analyze(request: DurAnalyzeRequest):
    return analyze_dur(request)


@router.get("/users/{user_id}/dur/latest")
def latest(user_id: str):
    return get_latest_dur(user_id)


@router.post("/dur/sync")
def sync(request: DurSyncRequest):
    return sync_mfds_dur(request)


@router.get("/dur/sync/diagnose")
def diagnose(risk_type: str = "병용금기"):
    return diagnose_dur_api_key(risk_type)
