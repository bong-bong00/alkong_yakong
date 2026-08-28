from fastapi import APIRouter, Query

from app.models.schemas import DrugExplainChatRequest

from app.services.drug_explain_service import get_drug_explanation


router = APIRouter(prefix="/api/v1", tags=["Drug Explain"])


@router.post("/drug-explain/chat")
def chat_with_pharmacist(request: DrugExplainChatRequest):
    from app.services.gemini_service import generate_chat_response
    reply = generate_chat_response(request.message, user_id=request.user_id)
    return {"reply": reply}


@router.get("/drug-explain/{medicine_code}")
def explain_drug(
    medicine_code: str,
    force_refresh: bool = Query(default=False),
):
    return get_drug_explanation(medicine_code, force_refresh=force_refresh)
