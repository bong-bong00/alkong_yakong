from fastapi import APIRouter

from app.models.schemas import DurAnalyzeRequest, DurSyncRequest
from app.models.response_schemas import (
    DurAnalyzeResponse,
    DurDiagnoseResponse,
    DurLatestResponse,
    DurSyncResponse,
)
from app.services.dur_service import analyze_dur, get_latest_dur
from app.services.dur_sync_service import diagnose_dur_api_key, sync_mfds_dur


router = APIRouter(prefix="/api/v1", tags=["DUR Analysis"])


@router.post(
    "/dur/analyze",
    response_model=DurAnalyzeResponse,
    response_model_exclude_unset=True,
)
def analyze(request: DurAnalyzeRequest):
    # 화면 요청은 로컬 자료로 즉시 판정한다. 외부 자료 갱신은 별도 동기화
    # 작업에서만 수행해 사용자의 화면 이동을 막지 않는다.
    return analyze_dur(request, refresh=False)


@router.get(
    "/users/{user_id}/dur/latest",
    response_model=DurLatestResponse,
    response_model_exclude_unset=True,
)
def latest(user_id: str):
    return get_latest_dur(user_id)


@router.post("/dur/sync", response_model=DurSyncResponse)
def sync(request: DurSyncRequest):
    return sync_mfds_dur(request)


@router.get("/dur/sync/diagnose", response_model=DurDiagnoseResponse)
def diagnose(risk_type: str = "병용금기"):
    return diagnose_dur_api_key(risk_type)
