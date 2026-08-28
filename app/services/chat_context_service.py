import json
from typing import Any

from app.database import get_connection


OFFICIAL_FIELDS_BY_INTENT = {
    "overview": ("product_name", "ingredient", "manufacturer", "efficacy"),
    "efficacy": ("product_name", "ingredient", "efficacy"),
    "usage": ("product_name", "usage"),
    "precautions": ("product_name", "cautions"),
    "side_effects": ("product_name", "side_effects"),
    "interaction": ("product_name", "ingredient", "interaction"),
    "combination": ("product_name", "ingredient", "interaction"),
    "age": ("product_name", "ingredient", "cautions"),
    "pregnancy": ("product_name", "ingredient", "cautions"),
    "duplicate": ("product_name", "ingredient", "efficacy"),
    "safety": ("product_name", "ingredient", "cautions", "interaction"),
    "storage": ("product_name", "storage"),
}

DUR_TYPES_BY_INTENT = {
    "interaction": {"병용금기"},
    "combination": {"병용금기"},
    "age": {"연령금기"},
    "pregnancy": {"임부금기"},
    "duplicate": {"효능군중복", "중복성분"},
    "safety": {"병용금기", "연령금기", "임부금기", "효능군중복", "중복성분"},
}

SAFETY_INTENTS = frozenset(DUR_TYPES_BY_INTENT)


def classify_question(message: str) -> set[str]:
    normalized = "".join(str(message or "").lower().split())
    intents: set[str] = set()
    if any(term in normalized for term in ("같이먹", "함께먹", "병용", "조합")):
        intents.add("combination")
    if any(term in normalized for term in ("상호작용", "다른약", "충돌")):
        intents.add("interaction")
    if any(term in normalized for term in ("나이", "연령", "몇살", "고령", "어린이")):
        intents.add("age")
    if any(term in normalized for term in ("임신", "임부", "임산부", "태아")):
        intents.add("pregnancy")
    if any(term in normalized for term in ("중복", "비슷한효과", "효능군")):
        intents.add("duplicate")
    if any(term in normalized for term in ("안전", "금기", "먹어도돼", "복용해도돼")):
        intents.add("safety")
    if any(term in normalized for term in ("부작용", "이상반응")):
        intents.add("side_effects")
    if any(term in normalized for term in ("주의", "경고", "조심")):
        intents.add("precautions")
    if any(term in normalized for term in ("어떻게먹", "복용법", "사용법", "용법", "몇번")):
        intents.add("usage")
    if any(term in normalized for term in ("효능", "효과", "어디에좋")):
        intents.add("efficacy")
    if any(term in normalized for term in ("보관", "저장")):
        intents.add("storage")
    if not intents or any(term in normalized for term in ("무슨약", "뭐야", "설명")):
        intents.add("overview")
    return intents


def is_safety_question(intents: set[str]) -> bool:
    return bool(intents & SAFETY_INTENTS)


def select_official_context(
    official_info: dict[str, Any],
    intents: set[str],
) -> dict[str, Any]:
    fields = {"medicine_code", "source"}
    for intent in intents:
        fields.update(OFFICIAL_FIELDS_BY_INTENT.get(intent, ()))
    return {
        field: official_info[field]
        for field in fields
        if official_info.get(field) not in (None, "", [])
    }


def load_latest_dur_context(user_id: str, intents: set[str]) -> list[dict[str, Any]]:
    wanted_types = set().union(
        *(DUR_TYPES_BY_INTENT.get(intent, set()) for intent in intents)
    )
    if not user_id or not wanted_types:
        return []

    conn = get_connection()
    try:
        row = conn.execute(
            """
            SELECT matches_json FROM risk_results
            WHERE user_id = ?
            ORDER BY created_at DESC, id DESC LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        if not row or not row["matches_json"]:
            return []
        try:
            matches = json.loads(row["matches_json"])
        except (TypeError, json.JSONDecodeError):
            return []

        result = []
        for match in matches if isinstance(matches, list) else []:
            if not isinstance(match, dict) or match.get("type") not in wanted_types:
                continue
            result.append(_enrich_dur_match(conn, match))
        return result
    finally:
        conn.close()


def _enrich_dur_match(conn, match: dict[str, Any]) -> dict[str, Any]:
    context = {
        "analysis_type": match.get("type"),
        "ingredient_a": match.get("ingredient_a"),
        "ingredient_b": match.get("ingredient_b"),
        "prohibition_or_caution": match.get("reason"),
        "source": match.get("source"),
    }
    external_id = match.get("external_id")
    if not external_id:
        return {key: value for key, value in context.items() if value not in (None, "")}

    row = conn.execute(
        """
        SELECT min_age, max_age, pregnancy_grade, notification_date, raw_json
        FROM dur_taboo WHERE external_id = ?
        ORDER BY updated_at DESC, id DESC LIMIT 1
        """,
        (external_id,),
    ).fetchone()
    if not row:
        return {key: value for key, value in context.items() if value not in (None, "")}

    raw = {}
    try:
        raw = json.loads(row["raw_json"] or "{}")
    except (TypeError, json.JSONDecodeError):
        pass
    context.update(
        {
            "prohibition_or_caution": raw.get("PROHBT_CONTENT")
            or context.get("prohibition_or_caution"),
            "age_base": raw.get("AGE_BASE"),
            "min_age": row["min_age"],
            "max_age": row["max_age"],
            "pregnancy_grade": row["pregnancy_grade"],
            "additional_remark": raw.get("REMARK"),
            "notification_date": row["notification_date"],
            "external_id": external_id,
        }
    )
    return {key: value for key, value in context.items() if value not in (None, "")}


def build_grounded_chat_prompt(
    *,
    message: str,
    intents: set[str],
    official_contexts: list[dict[str, Any]],
    dur_contexts: list[dict[str, Any]],
) -> str:
    official_text = (
        json.dumps(official_contexts, ensure_ascii=False, indent=2)
        if official_contexts
        else "현재 질문에 사용할 수 있는 e약은요 공식정보가 없습니다."
    )
    dur_text = (
        json.dumps(dur_contexts, ensure_ascii=False, indent=2)
        if dur_contexts
        else "현재 서버가 확인한 해당 유형의 DUR 분석 결과가 없습니다."
    )
    return f"""
당신은 어르신을 위한 알콩약콩 의약품 설명 도우미입니다.

반드시 지킬 규칙:
- 아래에 제공된 식약처 공식정보를 최우선 근거로 사용하세요.
- DUR 위험 여부를 새로 추론하거나 판정하지 마세요.
- 병용금기, 연령금기, 임부금기, 효능군중복 여부는 서버가 전달한 DUR 분석 결과만 설명하세요.
- 서버 DUR 결과가 없다는 사실을 안전하다는 뜻으로 해석하지 마세요.
- 공식 근거가 없는 안전성 질문에는 "현재 확인된 식약처 정보만으로는 확인하기 어렵습니다."라고 한계를 밝히세요.
- 공식정보에 없는 내용을 사실처럼 만들지 마세요.
- 원문의 의미를 바꾸지 말고 쉬운 한국어 3~5문장으로 설명하세요.
- 의사의 진단처럼 말하거나 복용 시작, 중단, 용량 변경을 지시하지 마세요.
- 필요한 경우 의사 또는 약사에게 확인하도록 안내하세요.

[사용자 질문]
{message}

[질문 의도]
{', '.join(sorted(intents))}

[식약처 e약은요 공식정보]
{official_text}

[식약처 DUR 서버 분석 결과]
{dur_text}
""".strip()
