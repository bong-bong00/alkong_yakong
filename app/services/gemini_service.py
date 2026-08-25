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


OCR_SCHEMA = {
    "type": "object",
    "properties": {
        "hospital_name": {"type": "string", "description": "병원 이름 (예: 서울대병원)"},
        "pharmacy_name": {"type": "string", "description": "약국 이름 (예: 종로약국)"},
        "prescribed_date": {"type": "string", "description": "처방 일자 (YYYY-MM-DD 형식)"},
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "drug_name": {"type": "string", "description": "약품명 (예: 모사피아정)"},
                    "dosage": {"type": "string", "description": "1회 투약량 (예: 1, 0.5 등)"},
                    "unit": {"type": "string", "description": "단위 (예: 정, 캡슐, ml)"},
                    "frequency_per_day": {"type": "integer", "description": "1일 투여 횟수 (예: 3)"},
                    "times_per_take": {"type": "integer", "description": "1회 투약 횟수/수량 (대부분 1)"},
                    "duration_days": {"type": "integer", "description": "총 투약 일수 (예: 7)"},
                    "easy_explanation": {"type": "string", "description": "약 봉투에 인쇄된 효능/효과 설명을 어르신이 이해하기 쉬운 일상어(예: 가라앉혀주는)로 번역한 1줄 설명"}
                },
                "required": ["drug_name", "frequency_per_day", "duration_days", "easy_explanation"]
            }
        }
    },
    "required": ["items"],
    "additionalProperties": False,
}


CHAT_EXTRACTION_SCHEMA = {
    "type": "object",
    "properties": {
        "drug_names": {
            "type": "array",
            "items": {"type": "string"},
            "description": "질문에 포함된 약품명 또는 성분명 목록 (없으면 빈 배열 반환)"
        }
    },
    "required": ["drug_names"],
    "additionalProperties": False,
}

import base64

def analyze_prescription_image(base64_image: str) -> dict[str, Any] | None:
    if not GEMINI_API_KEY:
        logger.info("GEMINI_API_KEY is not configured; cannot perform OCR.")
        return None

    try:
        from google import genai
        from google.genai import types

        if "," in base64_image:
            base64_image = base64_image.split(",")[1]
            
        base64_image = base64_image.strip()
        missing_padding = len(base64_image) % 4
        if missing_padding:
            base64_image += '=' * (4 - missing_padding)

        image_bytes = base64.b64decode(base64_image)
        part = types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg")

        prompt = (
            "이 사진은 한국의 병원 처방전 또는 약국 복약안내문입니다. "
            "이미지에서 약품명, 1회 투약량(dosage), 1일 투여 횟수(frequency_per_day), "
            "총 투약 일수(duration_days)를 정확하게 추출해주세요. "
            "정보가 보이지 않는다면 유추하지 말고 빈 문자열이나 null로 두세요.\n"
            "중요: 약품명 아래에 인쇄된 효능/효과 설명(예: 항염, 진정작용 등)을 반드시 찾아내고, "
            "이를 어르신들이 이해하기 쉬운 따뜻한 일상어(예: '가라앉혀주는', '편안하게 해주는')로 "
            "완벽하게 번역해서 'easy_explanation' 항목에 넣어주세요. 어려운 한자어나 의학용어는 절대 피하세요."
        )

        with genai.Client(api_key=GEMINI_API_KEY) as client:
            response = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=[part, prompt],
                config={
                    "temperature": 0.0,
                    "response_mime_type": "application/json",
                    "response_json_schema": OCR_SCHEMA,
                },
            )
            
        parsed = response.parsed
        if parsed is None and response.text:
            parsed = json.loads(response.text)
        if not isinstance(parsed, dict):
            raise ValueError("Gemini response was not a JSON object.")
        return parsed
    except Exception as error:
        logger.warning("Gemini OCR generation failed: %s", error, exc_info=True)
        return None

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


