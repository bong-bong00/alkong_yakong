from fastapi import APIRouter, Query

from app.models.schemas import DrugExplainChatRequest

from app.services.drug_explain_service import get_drug_explanation
from app.services.pharmacist.chat_pipeline import run_chat_pipeline
from app.services.pharmacist.suggestions import get_chat_suggestions


router = APIRouter(prefix="/api/v1", tags=["Drug Explain"])


@router.post("/drug-explain/chat")
def chat_with_pharmacist(request: DrugExplainChatRequest):
    suggestions = get_chat_suggestions(user_id=request.user_id)
    lexicon = [item["label"] for item in suggestions if item["type"] != "faq"]

    result = run_chat_pipeline(request.message, lexicon=lexicon)
    return {"reply": result.reply, "ok": result.ok, "trace": result.trace}


@router.get("/drug-explain/suggestions")
def chat_suggestions(
    q: str = Query(default="", max_length=100),
    user_id: str | None = Query(default=None, max_length=100),
):
    return {"items": get_chat_suggestions(q, user_id)}


@router.get("/drug-explain/{medicine_code}")
def explain_drug(
    medicine_code: str,
    force_refresh: bool = Query(default=False),
):
    return get_drug_explanation(medicine_code, force_refresh=force_refresh)
