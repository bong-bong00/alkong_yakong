"""Prescription image to raw OCR text."""

from __future__ import annotations

from dataclasses import dataclass

from app.core.config import GEMINI_API_KEY, GEMINI_MODEL


@dataclass(frozen=True)
class OcrEngineResult:
    raw_text: str
    engine_name: str
    confidence: float | None
    ok: bool
    error: str | None = None


def extract_raw_text(image_bytes: bytes) -> OcrEngineResult:
    if not image_bytes:
        return OcrEngineResult("", "none", None, False, "empty_image")
    if not GEMINI_API_KEY:
        return OcrEngineResult("", "gemini-vision", None, False, "missing_api_key")

    try:
        from google import genai
        from google.genai import types

        part = types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg")
        prompt = (
            "이 사진은 한국의 처방전 또는 약국 복약안내문입니다. "
            "사진에 보이는 글자를 원문 그대로 옮겨 적으세요. "
            "약품명, 용량, 복용 횟수, 투약 일수, 주의사항을 포함하세요. "
            "읽을 수 없는 내용은 추측하지 말고 생략하세요. "
            "JSON이나 설명을 붙이지 말고 인식한 원문만 반환하세요."
        )
        with genai.Client(api_key=GEMINI_API_KEY) as client:
            response = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=[part, prompt],
                config={"temperature": 0.0},
            )
        raw_text = str(getattr(response, "text", None) or "").strip()
        if not raw_text:
            return OcrEngineResult("", "gemini-vision", None, False, "empty_raw_text")
        return OcrEngineResult(raw_text, "gemini-vision", None, True)
    except Exception as error:
        return OcrEngineResult("", "gemini-vision", None, False, type(error).__name__)
