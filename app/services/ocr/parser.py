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
        if not isinstance(parsed, dict) or not parsed.get("items"):
            return None
        filtered = filter_to_source(parsed, text)
        return filtered if filtered.get("items") else None
    except (ImportError, ValueError, TypeError, json.JSONDecodeError):
        return None


def filter_to_source(parsed: dict[str, Any], raw_text: str) -> dict[str, Any]:
    """Drop invented drug names and numbers that are not in the OCR source."""
    source = raw_text or ""
    compact_source = _compact(source)
    items: list[dict[str, Any]] = []
    for item in parsed.get("items") or []:
        if not isinstance(item, dict):
            continue
        name = str(item.get("drug_name") or "").strip()
        if not name or not _name_in_source(name, compact_source):
            continue
        cleaned = dict(item)
        cleaned["drug_name"] = name
        for key in ("frequency_per_day", "times_per_take", "duration_days"):
            if key in cleaned and not _number_in_source(key, cleaned.get(key), source):
                cleaned.pop(key, None)
        items.append(cleaned)
    result = dict(parsed)
    result["items"] = items
    return result


def _compact(value: str) -> str:
    return "".join(str(value or "").casefold().split())


def _name_in_source(name: str, compact_source: str) -> bool:
    compact_name = _compact(name)
    return bool(compact_name) and compact_name in compact_source


def _number_in_source(key: str, value: Any, raw_text: str) -> bool:
    if value is None or value == "":
        return False
    try:
        number = str(int(value))
    except (TypeError, ValueError):
        number = str(value).strip()
    if not number:
        return False
    if key == "duration_days":
        return f"{number}일" in raw_text
    if key == "frequency_per_day":
        return f"{number}회" in raw_text or f"{number}번" in raw_text
    if key == "times_per_take":
        return (
            f"{number}정" in raw_text
            or f"{number}캡슐" in raw_text
            or f"{number}개" in raw_text
        )
    return number in raw_text
