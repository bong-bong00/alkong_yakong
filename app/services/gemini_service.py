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

OCR_PARSING_SCHEMA = {
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "drug_name": {"type": "string"},
            "dosage": {"type": "string"},
            "frequency_per_day": {"type": "integer"},
            "duration_days": {"type": "integer"},
            "warning_note": {"type": "string", "description": "보관방법 및 주의사항 (예: 실온보관, 수유주의 등)"}
        },
        "required": ["drug_name"],
        "additionalProperties": False,
    }
}

def parse_ocr_text_to_medicines(ocr_text: str) -> list[dict] | None:
    if not GEMINI_API_KEY:
        logger.info("GEMINI_API_KEY is not configured; fallback OCR applied.")
        return None

    try:
        from google import genai
        with genai.Client(api_key=GEMINI_API_KEY) as client:
            prompt = f"""
다음은 스마트폰 카메라로 촬영된 처방전의 OCR 텍스트입니다. 이 중에서 오직 처방된 '약품(의약품)' 정보만을 추출하세요.
각 약품별로 약품명(drug_name), 1회 투약량(dosage), 1일 투여 횟수(frequency_per_day), 총 투약 일수(duration_days)를 찾고, 
해당 약품에 대해 처방전에 특별히 명시된 보관방법이나 주의사항이 있다면 warning_note에 포함하여 JSON 배열 형태로 반환하세요.
(단, 약품과 무관한 병원명, 약국명 등은 무시하세요.)

[처방전 OCR 텍스트]
{ocr_text}
"""
            response = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=prompt.strip(),
                config={
                    "temperature": 0.1,
                    "response_mime_type": "application/json",
                    "response_json_schema": OCR_PARSING_SCHEMA,
                },
            )
        parsed = response.parsed
        if parsed is None and response.text:
            parsed = json.loads(response.text)
        if not isinstance(parsed, list):
            raise ValueError("Gemini response was not a JSON array.")
        return parsed
    except Exception as error:
        logger.warning("Gemini OCR parsing failed: %s", error, exc_info=True)
        return None
