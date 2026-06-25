from fastapi import APIRouter, Query

from app.models.schemas import DrugExplainChatRequest

from app.services.drug_explain_service import get_drug_explanation
from app.services.gemini_service import (
    DEMO_TYLENOL_SUMMARY_REPLY,
    _demo_chat_reply,
)


router = APIRouter(prefix="/api/v1", tags=["Drug Explain"])


@router.post("/drug-explain/chat")
def chat_with_pharmacist(request: DrugExplainChatRequest):
    from app.services.gemini_service import generate_chat_response
    reply = generate_chat_response(request.message)
    if "너무 바빠" in reply or "AI 약사가 설정" in reply:
        reply = _demo_chat_reply(request.message) or DEMO_TYLENOL_SUMMARY_REPLY
    return {"reply": reply}


@router.get("/drug-explain/{medicine_code}")
def explain_drug(
    medicine_code: str,
    force_refresh: bool = Query(default=False),
):
    return get_drug_explanation(medicine_code, force_refresh=force_refresh)
