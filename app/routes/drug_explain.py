from fastapi import APIRouter, HTTPException, Query

from app.models.schemas import DrugExplainChatRequest
from app.models.response_schemas import (
    ChatResponse,
    DrugExplanationResponse,
    DrugSearchResponse,
)

from app.services.drug_explain_service import get_drug_explanation
from app.services.external_api_service import search_drug_candidates


router = APIRouter(prefix="/api/v1", tags=["Drug Explain"])


@router.post("/drug-explain/chat", response_model=ChatResponse)
def chat_with_pharmacist(request: DrugExplainChatRequest):
    from app.services.gemini_service import generate_chat_response
    from app.services.pharmacist.conversation import conversation_context, resolve_followup
    history = [item.model_dump() for item in request.recent_history]
    selected = request.selected_medicine.model_dump() if request.selected_medicine else None
    selected_many = [item.model_dump() for item in request.selected_medicines]
    message, intent, selected, selected_many, clarification = resolve_followup(
        request.message, request.intent, history, selected, selected_many,
    )
    with conversation_context(history) as evidence:
        reply = clarification or generate_chat_response(
            message,
            user_id=request.user_id,
            selected_medicine=selected,
            selected_medicines=selected_many,
            temporary_medicines=[
                medicine.model_dump() for medicine in request.temporary_medicines
            ],
            intent=intent,
        )
    highlights = []
    if intent == "health_precautions":
        from app.services.pharmacist.health_precautions import health_highlight_terms
        highlights = health_highlight_terms(request.user_id, reply)
    return {"reply": reply, "health_highlight_terms": highlights,
            "sources": evidence["sources"], "conversation_medicines": evidence["medicines"],
            "resolved_intent": intent, "resolved_message": message,
            "resolved_scope": "selection" if selected or selected_many else None}


@router.get("/drugs/search", response_model=DrugSearchResponse)
def search_official_drugs(
    q: str = Query(..., min_length=1, max_length=80, description="의약품 품목명 검색어"),
):
    query = q.strip()
    if len(query) < 2:
        raise HTTPException(status_code=422, detail="검색어는 2글자 이상이어야 합니다.")
    return search_drug_candidates(query)


# 검토된 상세 카드만 읽는다. 화면 요청 중 외부 API·Gemini를 호출하지 않는다.
@router.get("/drug-explain/{medicine_code}", response_model=DrugExplanationResponse)
def explain_drug(
    medicine_code: str,
    force_refresh: bool = Query(default=False),
):
    return get_drug_explanation(medicine_code, force_refresh=force_refresh)
