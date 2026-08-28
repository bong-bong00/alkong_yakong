import json
import logging
import time
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


def _is_gemini_unavailable(error: Exception) -> bool:
    status_code = getattr(error, "status_code", None)
    code = getattr(error, "code", None)
    message = str(error).upper()
    return (
        status_code == 503
        or code == 503
        or ("503" in message and "UNAVAILABLE" in message)
    )


def _generate_content_with_retry(client, **kwargs):
    retry_delays = (1, 2)
    for attempt in range(len(retry_delays) + 1):
        try:
            return client.models.generate_content(**kwargs)
        except Exception as error:
            if not _is_gemini_unavailable(error) or attempt >= len(retry_delays):
                raise
            delay = retry_delays[attempt]
            logger.warning(
                "Gemini unavailable; retrying in %s second(s) (%s/2).",
                delay,
                attempt + 1,
            )
            time.sleep(delay)


def _read_response_text(response) -> str:
    try:
        return str(getattr(response, "text", None) or "")
    except Exception as error:
        logger.debug("Unable to read Gemini response.text: %s", error)
        return ""


def _complete_response_text(response, *, response_text: str | None = None) -> str:
    primary_text = (
        _read_response_text(response) if response_text is None else response_text
    )
    if primary_text:
        return primary_text.strip()

    completed_parts = []
    for candidate in getattr(response, "candidates", None) or []:
        content = getattr(candidate, "content", None)
        for part in getattr(content, "parts", None) or []:
            part_text = getattr(part, "text", None)
            if part_text:
                completed_parts.append(str(part_text))
    return "".join(completed_parts).strip()


def _finish_reasons(response) -> list[str]:
    reasons = []
    direct_reason = getattr(response, "finish_reason", None)
    if direct_reason is not None:
        reasons.append(str(direct_reason))
    for candidate in getattr(response, "candidates", None) or []:
        reason = getattr(candidate, "finish_reason", None)
        if reason is not None:
            reasons.append(str(reason))
    return reasons


def _finalize_chat_response(response) -> str:
    response_text = _read_response_text(response)
    logger.debug("Gemini response.text length: %d", len(response_text))

    reasons = _finish_reasons(response)
    if reasons:
        logger.debug("Gemini finish_reason: %s", ", ".join(reasons))

    reply = _complete_response_text(response, response_text=response_text)
    logger.debug("Gemini final reply length: %d", len(reply))

    has_valid_ending = reply.endswith((".", "요", "다", "니다"))
    if len(reply) < 20 or not has_valid_ending:
        logger.warning(
            "Gemini response may be incomplete: length=%d valid_ending=%s",
            len(reply),
            has_valid_ending,
        )
    if len(reply) < 20:
        return "응답 생성이 불완전했습니다. 다시 질문해주세요."
    return reply


def generate_chat_response(message: str, *, user_id: str = "") -> str:
    from app.services.chat_context_service import (
        build_grounded_chat_prompt,
        classify_question,
        is_safety_question,
        load_latest_dur_context,
        select_official_context,
    )

    intents = classify_question(message)
    safety_question = is_safety_question(intents)
    unavailable_reply = (
        "현재 확인된 식약처 정보만으로는 확인하기 어렵습니다. "
        "병용 가능 여부나 복용 안전성은 복용 중인 약 전체를 가지고 의사 또는 약사에게 확인해주세요."
        if safety_question
        else "현재 식약처 공식정보를 확인할 수 없어 답변하기 어렵습니다. 잠시 후 다시 시도해주세요."
    )
    if not GEMINI_API_KEY:
        return unavailable_reply

    try:
        from google import genai
        from app.services.external_api_service import search_drug_info_by_name

        with genai.Client(api_key=GEMINI_API_KEY) as client:
            # Step 0 & 1: 오타 교정 및 약품명 추출 (추론 강화)
            extract_prompt = (
                "당신은 제약 전문가입니다. 사용자의 질문에서 약품명이나 성분명을 추출해야 합니다.\n"
                "사용자가 약품명을 잘못 입력했거나(오타), 속어/줄임말을 사용했을 수 있습니다. "
                "의약품 정보는 아주 작은 오타로도 검색이 안 되거나 잘못된 결과가 나올 수 있으므로, "
                "반드시 머릿속으로 다음 3번의 검증(추론)을 거쳐 가장 정확한 명칭을 도출하세요:\n\n"
                "1. 원본 확인: 사용자가 입력한 단어 그대로 인식\n"
                "2. 오타 및 유사도 검증: 해당 단어가 흔한 오타인지, 혹은 시판되는 비슷한 이름의 정식 약품이 있는지 분석 (예: 타이래놀 -> 타이레놀, 후시딘 -> 부채표후시딘연고)\n"
                "3. 최종 확정: 식약처 DB에 검색될 확률이 가장 높은 '정확한 정식 제품명' 또는 '표준 성분명'으로 교정\n\n"
                "3단계 검증을 모두 마친 최종 확정된 약품명들만 'drug_names' 배열에 담아 JSON으로 반환하세요. 없으면 빈 배열을 반환하세요.\n\n"
                f"질문: {message}"
            )
            extract_response = _generate_content_with_retry(
                client,
                model=GEMINI_MODEL,
                contents=extract_prompt,
                config={
                    "temperature": 0.2,
                    "max_output_tokens": 256,
                    "response_mime_type": "application/json",
                    "response_json_schema": CHAT_EXTRACTION_SCHEMA,
                },
            )
            
            extracted_parsed = extract_response.parsed
            if extracted_parsed is None and extract_response.text:
                extracted_parsed = json.loads(extract_response.text)
                
            drug_names = []
            if isinstance(extracted_parsed, dict):
                drug_names = extracted_parsed.get("drug_names", [])

            # 2. 식약처 공식 데이터 수집
            official_data_list = []
            
            for name in drug_names:
                found_data = None
                # 2-1. 먼저 식약처 API 시도
                try:
                    search_result = search_drug_info_by_name(name)
                    if search_result and search_result.get("items"):
                        found_data = {
                            "검색된_약품명": name,
                            "match_type": search_result.get("match_type"),
                            "식약처_공식정보": search_result["items"][0],
                        }
                except Exception as e:
                    logger.warning("식약처 API 검색 실패 (%s): %s", name, e)
                
                if found_data:
                    official_data_list.append(found_data)

            official_contexts = [
                select_official_context(item["식약처_공식정보"], intents)
                for item in official_data_list
                if item.get("match_type") in {"exact", "partial"}
                and item.get("식약처_공식정보")
            ]
            official_contexts = [item for item in official_contexts if item]
            dur_contexts = load_latest_dur_context(user_id, intents)

            if not official_contexts and not dur_contexts:
                return unavailable_reply

            prompt = build_grounded_chat_prompt(
                message=message,
                intents=intents,
                official_contexts=official_contexts,
                dur_contexts=dur_contexts,
            )

            response = _generate_content_with_retry(
                client,
                model=GEMINI_MODEL,
                contents=prompt,
                config={"temperature": 0.2, "max_output_tokens": 512},
            )
            return _finalize_chat_response(response)
    except Exception as error:
        logger.warning("Gemini chat failed: %s", error, exc_info=True)
        return unavailable_reply
