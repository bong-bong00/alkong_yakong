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


def _mime_type(image_bytes: bytes) -> str:
    if image_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if image_bytes[:2] == b"\xff\xd8":
        return "image/jpeg"
    if image_bytes[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif"
    if image_bytes[:4] == b"RIFF" and image_bytes[8:12] == b"WEBP":
        return "image/webp"
    return "image/jpeg"


def _error_code(error: Exception) -> str:
    text = f"{type(error).__name__} {error}".lower()
    if "timeout" in text or "deadline" in text:
        return "timeout"
    if "401" in text or "403" in text or "api key" in text or "unauth" in text:
        return "auth_error"
    if "503" in text or "unavailable" in text:
        return "unavailable"
    return type(error).__name__


def extract_raw_text(image_bytes: bytes) -> OcrEngineResult:
    if not image_bytes:
        return OcrEngineResult("", "none", None, False, "empty_image")
    if not GEMINI_API_KEY:
        return OcrEngineResult("", "gemini-vision", None, False, "missing_api_key")

    try:
        from google import genai
        from google.genai import types

        part = types.Part.from_bytes(
            data=image_bytes, mime_type=_mime_type(image_bytes)
        )
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
        return OcrEngineResult(
            "", "gemini-vision", None, False, _error_code(error)
        )
