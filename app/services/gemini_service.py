"""Compatibility wrappers. OCR lives in ocr/, cards in pharmacist/generate."""

from typing import Any

from app.services.pharmacist.generate import generate_card_from_source


def generate_easy_explanation(
    official_info: dict[str, Any],
) -> dict[str, Any] | None:
    try:
        return generate_card_from_source(official_info)
    except (ValueError, RuntimeError, ImportError, TypeError):
        return None
