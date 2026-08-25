"""Prescription raw text to structured medicine data."""

from __future__ import annotations

import json
from typing import Any

from app.core.config import GEMINI_API_KEY, GEMINI_MODEL


PRESCRIPTION_SCHEMA = {
    "type": "object",
    "properties": {
        "hospital_name": {"type": "string"},
        "pharmacy_name": {"type": "string"},
        "prescribed_date": {"type": "string"},
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "drug_name": {"type": "string"},
                    "dosage": {"type": "string"},
                    "unit": {"type": "string"},
                    "frequency_per_day": {"type": "integer"},
                    "times_per_take": {"type": "integer"},
                    "duration_days": {"type": "integer"},
                    "easy_explanation": {"type": "string"},
                    "warning_note": {"type": "string"},
                },
                "required": ["drug_name"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["items"],
    "additionalProperties": False,
}


def parse_prescription_text(raw_text: str) -> dict[str, Any] | None:
    text = (raw_text or "").strip()
    if not text or not GEMINI_API_KEY:
        return None
    try:
        from google import genai

        prompt = (
            "아래 처방전 원문만 근거로 구조화하세요. "
            "원문에 없는 약 이름, 용량, 횟수, 기간을 추측하지 마세요. "
            "확인되지 않는 항목은 생략하세요.\n\n"
            f"처방전 원문:\n{text}"
        )
        with genai.Client(api_key=GEMINI_API_KEY) as client:
            response = client.models.generate_content(
                model=GEMINI_MODEL,
                contents=prompt,
                config={
                    "temperature": 0.0,
                    "response_mime_type": "application/json",
                    "response_json_schema": PRESCRIPTION_SCHEMA,
                },
            )
        parsed = getattr(response, "parsed", None)
        if parsed is None:
            response_text = str(getattr(response, "text", None) or "")
            parsed = json.loads(response_text) if response_text else None
        return parsed if isinstance(parsed, dict) and parsed.get("items") else None
    except (ImportError, ValueError, TypeError, json.JSONDecodeError):
        return None
