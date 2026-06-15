import json
import logging
from typing import Any

from app.core.config import GEMINI_API_KEY, GEMINI_MODEL


logger = logging.getLogger(__name__)

EXPLANATION_SCHEMA = {
    "type": "object",
    "properties": {
        "easy_summary": {"type": "string"},
        "what_it_does": {"type": "string"},
        "how_to_take": {"type": "string"},
        "cautions": {"type": "array", "items": {"type": "string"}},
        "possible_side_effects": {
            "type": "array",
            "items": {"type": "string"},
        },
        "storage": {"type": "string"},
        "ask_doctor_when": {
            "type": "array",
            "items": {"type": "string"},
        },
        "source_based": {"type": "boolean"},
    },
    "required": [
        "easy_summary",
        "what_it_does",
        "how_to_take",
        "cautions",
        "possible_side_effects",
        "storage",
        "ask_doctor_when",
        "source_based",
    ],
    "additionalProperties": False,
}


def generate_easy_explanation(
    official_info: dict[str, Any],
) -> dict[str, Any] | None:
    if not GEMINI_API_KEY:
        logger.info("GEMINI_API_KEY is not configured; using official-data fallback.")
        return None

    try:
        from google import genai

        with genai.Client(api_key=GEMINI_API_KEY) as client:
            response = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=_build_prompt(official_info),
                config={
                    "temperature": 0.1,
                    "response_mime_type": "application/json",
                    "response_json_schema": EXPLANATION_SCHEMA,
                },
            )
        parsed = response.parsed
        if parsed is None and response.text:
            parsed = json.loads(response.text)
        if not isinstance(parsed, dict):
            raise ValueError("Gemini response was not a JSON object.")
        return _normalize_card(parsed)
    except (ImportError, ValueError, TypeError, json.JSONDecodeError) as error:
        logger.warning("Gemini explanation generation failed: %s", error, exc_info=True)
        return None
    except Exception as error:
        logger.warning("Gemini API request failed: %s", error, exc_info=True)
        return None


def _normalize_card(value: dict[str, Any]) -> dict[str, Any]:
    return {
        "easy_summary": _text(value.get("easy_summary")),
        "what_it_does": _text(value.get("what_it_does")),
        "how_to_take": _text(value.get("how_to_take")),
        "cautions": _string_list(value.get("cautions")),
        "possible_side_effects": _string_list(
            value.get("possible_side_effects")
        ),
        "storage": _text(value.get("storage")),
        "ask_doctor_when": _string_list(value.get("ask_doctor_when")),
        "source_based": bool(value.get("source_based", True)),
    }


def _text(value: Any) -> str:
    return str(value or "").strip()


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        value = [value] if value else []
    return [text for item in value if (text := _text(item))]


def _build_prompt(official_info: dict[str, Any]) -> str:
    official_json = json.dumps(official_info, ensure_ascii=False, indent=2)
    return f"""
아래에 제공된 공식 e약은요 원문만 근거로 고령자가 읽기 쉬운 약 설명 카드를 작성하세요.

반드시 지킬 조건:
- 공식 정보에 없는 내용을 추측하거나 일반 의학 지식으로 보충하지 마세요.
- 정보가 없으면 정확히 "공식 정보에 명시되어 있지 않습니다"라고 쓰세요.
- 어려운 의학 용어는 뜻을 바꾸지 않는 범위에서 쉬운 말로 바꾸세요.
- 짧고 분명한 한국어 문장을 사용하세요.
- 진단하거나 처방하는 것처럼 말하지 마세요.
- ask_doctor_when에는 이상 증상이 있거나 복용이 걱정될 때
  "의사/약사와 상담하세요"라는 안내를 반드시 포함하세요.
- source_based는 반드시 true로 반환하세요.
- 지정된 JSON 스키마 이외의 설명이나 마크다운을 출력하지 마세요.

공식 e약은요 정보:
{official_json}
""".strip()
