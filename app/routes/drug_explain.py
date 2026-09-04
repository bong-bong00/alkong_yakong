from fastapi import APIRouter, Query

from app.models.schemas import DrugExplainChatRequest

from app.services.drug_explain_service import get_drug_explanation
from app.services.pharmacist.chat_pipeline import run_chat_pipeline
from app.services.pharmacist.suggestions import get_chat_suggestions


router = APIRouter(prefix="/api/v1", tags=["Drug Explain"])


@router.post("/drug-explain/chat")
def chat_with_pharmacist(request: DrugExplainChatRequest):
    # 오늘 약 + 입력 문장으로 뜨는 자동완성 약 이름을 사전으로 씀.
    # (아산형: 고른/친 약 이름이 매칭 후보가 됨)
    base = get_chat_suggestions(user_id=request.user_id)
    typed = get_chat_suggestions(request.message, user_id=request.user_id)
    lexicon: list[str] = []
    seen: set[str] = set()
    for item in [*base, *typed]:
        if item.get("type") == "faq":
            continue
        label = str(item.get("label") or "").strip()
        if label and label not in seen:
            seen.add(label)
            lexicon.append(label)

    result = run_chat_pipeline(
        request.message,
        lexicon=lexicon,
        user_id=request.user_id,
    )
    payload = {"reply": result.reply, "ok": result.ok, "trace": result.trace}
    source_label = result.trace.get("source_label")
    if source_label:
        payload["source_label"] = source_label
    candidates = result.trace.get("candidates")
    if isinstance(candidates, list) and candidates:
        payload["candidates"] = candidates
    return payload


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
