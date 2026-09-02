"""Prescription image to raw OCR text."""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO

from app.core.config import GEMINI_API_KEY, GEMINI_MODEL

# 휴대폰 원본(수 MB)은 전송·인식이 느려져서, OCR 전에 긴 변을 줄인다.
_MAX_EDGE_PX = 1600
_JPEG_QUALITY = 85


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


def _prepare_image(image_bytes: bytes) -> tuple[bytes, str]:
    """너무 큰 사진은 JPEG로 줄여 Gemini 전송 실패·지연을 줄인다."""
    try:
        from PIL import Image

        with Image.open(BytesIO(image_bytes)) as image:
            image = image.convert("RGB")
            width, height = image.size
            longest = max(width, height)
            if longest > _MAX_EDGE_PX:
                scale = _MAX_EDGE_PX / float(longest)
                image = image.resize(
                    (max(1, int(width * scale)), max(1, int(height * scale))),
                    Image.Resampling.LANCZOS,
                )
            elif len(image_bytes) < 1_500_000 and _mime_type(image_bytes) == "image/jpeg":
                return image_bytes, "image/jpeg"
            buffer = BytesIO()
            image.save(buffer, format="JPEG", quality=_JPEG_QUALITY, optimize=True)
            return buffer.getvalue(), "image/jpeg"
    except Exception:
        return image_bytes, _mime_type(image_bytes)


def _error_code(error: Exception) -> str:
    text = f"{type(error).__name__} {error}".lower()
    if "timeout" in text or "deadline" in text:
        return "timeout"
    if "429" in text or "resource_exhausted" in text or "quota" in text:
        return "quota_exceeded"
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

        prepared_bytes, mime_type = _prepare_image(image_bytes)
        part = types.Part.from_bytes(data=prepared_bytes, mime_type=mime_type)
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
