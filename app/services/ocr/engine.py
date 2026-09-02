"""Prescription image to raw OCR text.

우선순위:
  1) Gemini Vision (기본)
  2) Gemini 할당량/키 실패 시 → CLOVA OCR (자격증명 있을 때)
  3) CLOVA_OCR_ENABLED=true 이면 CLOVA를 먼저 시도
"""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO

from app.core.config import (
    CLOVA_OCR_API_URL,
    CLOVA_OCR_ENABLED,
    CLOVA_OCR_SECRET_KEY,
    GEMINI_API_KEY,
    GEMINI_MODEL,
)

# 휴대폰 원본(수 MB)은 전송·인식이 느려져서, OCR 전에 긴 변을 줄인다.
_MAX_EDGE_PX = 1600
_JPEG_QUALITY = 85

# Gemini 실패 시 CLOVA로 넘길 오류
_GEMINI_FALLBACK_ERRORS = frozenset(
    {
        "quota_exceeded",
        "missing_api_key",
        "auth_error",
        "unavailable",
        "timeout",
        "empty_raw_text",
    }
)


@dataclass(frozen=True)
class OcrEngineResult:
    raw_text: str
    engine_name: str
    confidence: float | None
    ok: bool
    error: str | None = None
    fallback_from: str | None = None


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
    """큰 사진은 줄이고, 대비·선명을 조금 올려 표 글자 인식률을 높인다."""
    try:
        from PIL import Image, ImageEnhance, ImageOps

        with Image.open(BytesIO(image_bytes)) as image:
            image = image.convert("RGB")
            image = ImageOps.exif_transpose(image)
            width, height = image.size
            longest = max(width, height)
            if longest > _MAX_EDGE_PX:
                scale = _MAX_EDGE_PX / float(longest)
                image = image.resize(
                    (max(1, int(width * scale)), max(1, int(height * scale))),
                    Image.Resampling.LANCZOS,
                )
            image = ImageEnhance.Contrast(image).enhance(1.15)
            image = ImageEnhance.Sharpness(image).enhance(1.1)
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


def _clova_ready() -> bool:
    return bool(CLOVA_OCR_API_URL and CLOVA_OCR_SECRET_KEY)


def _extract_with_gemini(image_bytes: bytes) -> OcrEngineResult:
    if not GEMINI_API_KEY:
        return OcrEngineResult("", "gemini-vision", None, False, "missing_api_key")
    try:
        from google import genai
        from google.genai import types

        prepared_bytes, mime_type = _prepare_image(image_bytes)
        part = types.Part.from_bytes(data=prepared_bytes, mime_type=mime_type)
        prompt = (
            "이 사진은 한국의 처방전 또는 약국 복약안내문입니다. "
            "사진에 보이는 글자를 원문 그대로 옮겨 적으세요.\n"
            "특히 약 표가 있으면 각 약마다 아래를 빠뜨리지 마세요:\n"
            "- 약품명\n"
            "- 1회 투약량\n"
            "- 1일 투여횟수\n"
            "- 투약 일수 (며칠분)\n"
            "표는 가능하면 '약이름 | 설명 | 투약량 | 횟수 | 일수' 형태로 줄마다 적으세요.\n"
            "병원명, 조제약사, 조제일자도 포함하세요.\n"
            "읽을 수 없는 내용만 생략하고, 보이는 숫자는 추측으로 바꾸지 마세요.\n"
            "JSON이나 설명 문장 없이 인식한 원문만 반환하세요."
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


def _extract_with_clova(image_bytes: bytes) -> OcrEngineResult:
    if not _clova_ready():
        return OcrEngineResult("", "clova-ocr", None, False, "missing_clova_credentials")
    try:
        from app.services.ocr.clova_engine import extract_with_clova

        prepared_bytes, _mime = _prepare_image(image_bytes)
        result = extract_with_clova(
            prepared_bytes,
            image_name="prescription.jpg",
            enable_table_detection=False,
        )
        if not result.ok:
            return OcrEngineResult(
                "", "clova-ocr", None, False, result.error or "clova_failed"
            )
        return OcrEngineResult(result.raw_text, "clova-ocr", None, True)
    except Exception as error:
        return OcrEngineResult("", "clova-ocr", None, False, _error_code(error))


def extract_raw_text(image_bytes: bytes) -> OcrEngineResult:
    """Gemini 우선, 실패(할당량 등) 시 CLOVA로 폴백."""
    if not image_bytes:
        return OcrEngineResult("", "none", None, False, "empty_image")

    # 강제 CLOVA 우선 (테스트/할당량 절약용)
    if CLOVA_OCR_ENABLED and _clova_ready():
        clova_first = _extract_with_clova(image_bytes)
        if clova_first.ok:
            return clova_first

    gemini = _extract_with_gemini(image_bytes)
    if gemini.ok:
        return gemini

    # Gemini 할당량·키·일시 장애면 CLOVA로
    if gemini.error in _GEMINI_FALLBACK_ERRORS and _clova_ready():
        clova = _extract_with_clova(image_bytes)
        if clova.ok:
            return OcrEngineResult(
                clova.raw_text,
                "clova-ocr",
                None,
                True,
                fallback_from=f"gemini:{gemini.error}",
            )
        return OcrEngineResult(
            "",
            "clova-ocr",
            None,
            False,
            error=clova.error or "clova_failed",
            fallback_from=f"gemini:{gemini.error}",
        )

    return gemini
