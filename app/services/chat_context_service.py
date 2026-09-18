import json
from collections import Counter
from typing import Any

from app.database import get_connection
from app.services.pharmacist.ingredient import (
    is_usable_ingredient,
    normalize_ingredient,
)


OFFICIAL_FIELDS_BY_INTENT = {
    "overview": ("product_name", "ingredient", "manufacturer", "efficacy"),
    "efficacy": ("product_name", "ingredient", "efficacy"),
    "dosage": ("product_name", "usage"),
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
EXPLICIT_QUESTION_INTENTS = frozenset(
    {
        "efficacy",
        "dosage",
        "precautions",
        "side_effects",
        "combination",
        "age",
        "pregnancy",
        "duplicate",
    }
)


def general_conversation_reply(message: str) -> str | None:
    normalized = "".join(ch for ch in str(message or "").lower() if ch.isalnum())
    if normalized in {"안녕", "안녕하세요"}:
        return (
            "안녕하세요. 복용 중인 약이나 약의 효능, 복용법, "
            "주의사항, 상호작용 등에 대해 질문해주세요."
        )
    if normalized in {"고마워", "고마워요", "감사", "감사합니다"}:
        return "도움이 되어 기뻐요. 다른 약 정보가 궁금하면 편하게 물어보세요."
    if normalized in {"너는뭐야", "무슨기능이있어"}:
        return (
            "식약처 e약은요 공식정보와 서버에서 확인한 DUR 분석 결과를 "
            "바탕으로 약의 효능, 복용법, 주의사항, 부작용, 상호작용 등을 "
            "쉽게 설명해드릴 수 있습니다."
        )
    return None


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


def resolve_question_intents(
    message: str,
    explicit_intent: str | None = None,
) -> set[str]:
    if explicit_intent in EXPLICIT_QUESTION_INTENTS:
        return {explicit_intent}
    return classify_question(message)


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


def load_latest_dur_context(user_id: str, intents: set[str]) -> dict[str, Any]:
    wanted_types = set().union(
        *(DUR_TYPES_BY_INTENT.get(intent, set()) for intent in intents)
    )
    if not wanted_types:
        return {"status": "not_required", "items": []}
    if not user_id:
        return {"status": "missing", "items": []}

    conn = get_connection()
    try:
        row = conn.execute(
            """
            SELECT analyzed_ingredients, matches_json FROM risk_results
            WHERE user_id = ?
            ORDER BY created_at DESC, id DESC LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        if not row:
            return {"status": "missing", "items": []}

        current_rows = conn.execute(
            """
            SELECT m.*
            FROM medicines m
            WHERE m.medicine_code IN (
                SELECT DISTINCT um.medicine_code
                FROM user_medicines um
                WHERE um.user_id = ? AND um.is_active = 1
            )
            ORDER BY m.medicine_code
            """,
            (user_id,),
        ).fetchall()
        current = [
            item["ingredient"]
            for item in current_rows
            if is_usable_ingredient(
                item["ingredient"],
                item["product_name"] if "product_name" in item.keys() else None,
            )
        ]
        analyzed = _json_list(row["analyzed_ingredients"])
        if _ingredient_signature(current) != _ingredient_signature(analyzed):
            return {"status": "stale", "items": []}

        matches = _json_list(row["matches_json"])

        result = []
        for match in matches if isinstance(matches, list) else []:
            if not isinstance(match, dict) or match.get("type") not in wanted_types:
                continue
            result.append(_enrich_dur_match(conn, match))
        return {"status": "current", "items": result}
    finally:
        conn.close()


def _json_list(value: Any) -> list[Any]:
    if isinstance(value, list):
        return value
    if not value:
        return []
    try:
        parsed = json.loads(value)
    except (TypeError, json.JSONDecodeError):
        return []
    return parsed if isinstance(parsed, list) else []


def _ingredient_signature(values: list[Any]) -> Counter:
    return Counter(
        normalized
        for value in values
        if (normalized := normalize_ingredient(str(value or "")))
    )


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


def enrich_dur_matches(matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
    conn = get_connection()
    try:
        return [_enrich_dur_match(conn, match) for match in matches]
    finally:
        conn.close()


def build_grounded_chat_prompt(
    *,
    message: str,
    intents: set[str],
    official_contexts: list[dict[str, Any]],
    dur_result: dict[str, Any],
) -> str:
    official_text = (
        json.dumps(official_contexts, ensure_ascii=False, indent=2)
        if official_contexts
        else "현재 질문에 사용할 수 있는 식약처 공식정보가 없습니다."
    )
    dur_text = (
        json.dumps(dur_result["items"], ensure_ascii=False, indent=2)
        if dur_result["items"]
        else "현재 서버가 확인한 해당 유형의 DUR 분석 결과가 없습니다."
    )
    return f"""
당신은 어르신을 위한 알콩약콩 의약품 설명 도우미입니다.

반드시 지킬 규칙:
- 아래에 제공된 식약처 공식정보를 최우선 근거로 사용하세요. e약은요 정보가 있으면 우선하고, 없을 때는 정확한 품목으로 검증된 의약품 허가정보만 사용하세요.
- DUR 위험 여부를 새로 추론하거나 판정하지 마세요.
- 병용금기, 연령금기, 임부금기, 효능군중복 여부는 서버가 전달한 DUR 분석 결과만 설명하세요.
- 연령금기와 임부금기는 official_criteria를 약 자체의 공식 기준으로 먼저 설명하세요.
- user_applicability는 사용자 프로필 기준 참고 정보입니다. unknown이면 개인 적용 여부를 판단하지 말고, not_applicable이어도 약 자체의 공식 기준을 생략하지 마세요.
- user_applicability가 applicable이어도 복용 금지나 위험을 새로 단정하지 말고, 공식 기준과 관련될 수 있으므로 의료진 또는 약사에게 확인하도록 안내하세요.
- 서버 DUR 결과가 없다는 사실을 안전하다는 뜻으로 해석하지 마세요.
- 공식 근거가 없는 안전성 질문에는 "현재 확인된 식약처 정보만으로는 확인하기 어렵습니다."라고 한계를 밝히세요.
- 공식정보에 없는 내용을 사실처럼 만들지 마세요.
- 질문에 대한 핵심 답을 첫 문장에 쓰고, 쉬운 한국어의 짧은 문단으로 설명하세요.
- 일반 사용자가 일상적으로 쓰지 않는 의학·해부학·약학 전문용어는 답변에 그대로 쓰지 말고, 뜻을 보존한 쉬운 한국어로 바꿔 설명하세요. 전문용어를 괄호 안에 덧붙이지 마세요.
- 예를 들어 융모는 "장 안쪽의 작은 돌기", 상피는 "몸 표면이나 장기를 덮는 얇은 층", 수용체는 "약 성분이 작용하는 몸속 부분", 대사는 "몸이 약을 처리하는 과정", 흡수는 "약 성분이 몸 안으로 들어오는 과정"으로 설명하세요.
- 배설은 "몸 밖으로 내보내는 과정", 분비는 "몸에서 특정 물질을 만들어 내보내는 과정", 효소는 "몸속에서 화학 작용을 돕는 물질", 혈중농도는 "피 속에 약 성분이 얼마나 있는지", 반감기는 "약 성분의 양이 절반으로 줄어드는 데 걸리는 시간"으로 설명하세요.
- 적응증은 "이 약을 사용하는 질환이나 증상", 금기는 "복용하면 안 되는 경우", 상호작용은 "함께 먹을 때 생길 수 있는 영향", 이상반응은 "복용 후 나타날 수 있는 불편한 증상"으로 설명하세요.
- 병용금기는 "함께 먹으면 안 되는 조합", 연령금기는 "특정 나이에 주의가 필요한 내용", 임부금기는 "임신 중 피해야 할 수 있는 내용", 효능군중복은 "비슷한 효과의 약이 겹치는 경우", 투여는 "복용", 용법은 "먹는 방법"으로 바꿔 설명하세요.
- 정확성을 위해 주성분, 복용량, 공식 의약품명·제품명·성분명은 원래 표현을 유지하세요. 그 명칭을 설명하는 문장만 쉬운 말로 쓰세요.
- 문맥이 불분명하거나 공식 자료에 쉬운 설명이 없으면 추측하지 말고, 확인할 수 없다고 알리며 의료적 판단을 단정하지 마세요.
- 제공된 근거가 있는 경우에만 다음 제목을 사용할 수 있습니다: 핵심 요약, 공식 정보, DUR 안내, 다음 안내.
- 해당 근거가 없거나 확인할 수 없는 항목은 제목과 내용을 만들지 마세요.
- 제목 아래에는 제공된 공식정보 또는 서버 DUR 결과만 설명하고, 원문의 의미를 바꾸지 마세요.
- 최종 답변은 3~5개의 짧은 문장 또는 짧은 문단으로 작성하세요.
- 의사의 진단처럼 말하거나 복용 시작, 중단, 용량 변경을 지시하지 마세요.
- 필요한 경우 의사 또는 약사에게 확인하도록 안내하세요.

[사용자 질문]
{message}

[질문 의도]
{', '.join(sorted(intents))}

[식약처 공식 의약품 정보]
{official_text}

[DUR 분석 결과 상태]
{dur_result['status']}

[식약처 DUR 서버 분석 결과]
{dur_text}
""".strip()
