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


def generate_chat_response(message: str) -> str:
    if not GEMINI_API_KEY:
        return "죄송합니다. AI 약사가 설정되지 않았습니다."

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
            extract_response = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=extract_prompt,
                config={
                    "temperature": 0.0,
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

            # 2. 식약처 오피셜 데이터 수집 및 로컬 DB 풀백
            from app.database import get_connection
            official_data_list = []
            
            for name in drug_names:
                found_data = None
                # 2-1. 먼저 식약처 API 시도
                try:
                    search_result = search_drug_info_by_name(name)
                    if search_result and search_result.get("items"):
                        found_data = {"검색된_약품명": name, "식약처_공식정보": search_result["items"][0]}
                except Exception as e:
                    logger.warning("식약처 API 검색 실패 (%s): %s", name, e)
                
                # 2-2. API 실패 또는 결과가 없으면 로컬 DB(medicines) 검색
                if not found_data:
                    conn = get_connection()
                    try:
                        cursor = conn.cursor()
                        # 이름이 포함된 약품 검색
                        row = cursor.execute(
                            "SELECT * FROM medicines WHERE product_name LIKE ? OR ingredient LIKE ? LIMIT 1",
                            (f"%{name}%", f"%{name}%")
                        ).fetchone()
                        if row:
                            found_data = {"검색된_약품명": name, "로컬DB_저장정보": dict(row)}
                    finally:
                        conn.close()
                
                if found_data:
                    official_data_list.append(found_data)

            # 3. 최종 답변 생성
            prompt = (
                "당신은 어르신들을 위한 다정하고 친절한 AI 약사 '알콩약콩'입니다. "
                "사용자의 다음 질문이나 인사에 쉽고 따뜻한 말투로 대답해주세요. "
                "어려운 의학 용어는 피하고 친근하게 답변해주세요.\n"
                "중요: 모바일 화면에서 읽기 편하도록, 답변은 핵심만 요약해서 반드시 3~4문장 이내로 아주 짧고 간결하게 작성하세요.\n\n"
            )
            
            if official_data_list:
                prompt += (
                    "중요: 아래 식약처 공식 데이터가 검색되었습니다. 반드시 아래 데이터를 기반으로 "
                    "정확하게 대답하세요. 공식 데이터에 없는 내용은 함부로 유추하거나 일반적인 지식으로 덧붙이지 마세요. "
                    "대답의 앞이나 뒤에 '식약처 공식 정보에 따르면~' 이라는 뉘앙스를 자연스럽게 포함하세요.\n\n"
                    f"[식약처 공식 데이터]\n{json.dumps(official_data_list, ensure_ascii=False, indent=2)}\n\n"
                )
            elif drug_names:
                prompt += (
                    "참고: 사용자가 특정 약품명을 언급했으나, 식약처 공식 DB에서 데이터를 찾지 못했습니다. "
                    "답변 시 '정확한 제품 정보는 식약처 DB에서 찾을 수 없지만, 일반적인 성분 정보로 안내해 드릴게요' "
                    "라고 부드럽게 안내한 뒤 일반적인 지식 내에서 답변해주세요.\n\n"
                )
                
            prompt += f"사용자: {message}"

            response = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=prompt,
                config={"temperature": 0.3},
            )
            return response.text.strip()
    except Exception as error:
        logger.warning("Gemini chat failed: %s", error, exc_info=True)
        return "죄송합니다. 지금은 AI 약사가 너무 바빠서 대답할 수 없어요. 잠시 후 다시 시도해주세요."
