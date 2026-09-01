"""Prescription raw text to structured medicine data."""

from __future__ import annotations

import json
import re
from typing import Any

from app.core.config import GEMINI_API_KEY, GEMINI_MODEL


# 앱·DB가 기대하는 정형 필드. drug_name만 필수, 나머지는 원문에 있을 때만 채운다.
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

# 인식률·커버리지 계산에 쓰는 핵심 필드 (헤더 + 약 항목)
HEADER_FIELDS = ("hospital_name", "pharmacy_name", "prescribed_date")
ITEM_FIELDS = (
    "drug_name",
    "dosage",
    "unit",
    "frequency_per_day",
    "times_per_take",
    "duration_days",
)


def parse_prescription_text(raw_text: str) -> dict[str, Any] | None:
    text = (raw_text or "").strip()
    if not text or not GEMINI_API_KEY:
        return None
    try:
        from google import genai

        prompt = (
            "아래 처방전/복약안내 원문만 근거로 JSON 구조화하세요.\n"
            "규칙:\n"
            "1) 원문에 없는 약 이름·용량·횟수·기간을 추측하지 마세요.\n"
            "2) 확인되지 않는 항목은 생략하세요.\n"
            "3) 표 형식이면 열을 이렇게 매핑하세요.\n"
            "   - 약품명 및 용량 → drug_name (+ 필요 시 dosage/unit)\n"
            "   - 1회 투약량 → dosage 또는 times_per_take\n"
            "   - 1일 투여횟수 → frequency_per_day (정수)\n"
            "   - 투약 일수 → duration_days (정수)\n"
            "4) 복용법/효능 설명 문장은 easy_explanation에 넣으세요.\n"
            "5) prescribed_date는 YYYY-MM-DD로 정규화하세요.\n"
            "6) hospital_name은 병원/의원명, pharmacy_name은 약국명 또는 조제약사명.\n\n"
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
        if not filtered.get("items"):
            return None
        filtered["field_coverage"] = measure_field_coverage(filtered)
        return filtered
    except Exception:
        # 할당량(429)·네트워크 등도 parse_failed로 올려 파이프라인이 죽지 않게 한다.
        return None


def measure_field_coverage(structured: dict[str, Any]) -> dict[str, Any]:
    """구조화 결과에서 핵심 필드가 얼마나 채워졌는지(커버리지)를 계산한다."""
    header_hit = sum(1 for key in HEADER_FIELDS if str(structured.get(key) or "").strip())
    header_total = len(HEADER_FIELDS)

    item_hit = 0
    item_total = 0
    per_item: list[dict[str, Any]] = []
    for item in structured.get("items") or []:
        if not isinstance(item, dict):
            continue
        filled = []
        missing = []
        for key in ITEM_FIELDS:
            item_total += 1
            value = item.get(key)
            ok = value is not None and str(value).strip() != ""
            if ok:
                item_hit += 1
                filled.append(key)
            else:
                missing.append(key)
        per_item.append(
            {
                "drug_name": item.get("drug_name"),
                "filled": filled,
                "missing": missing,
                "item_coverage_pct": round(100.0 * len(filled) / len(ITEM_FIELDS), 1),
            }
        )

    total_hit = header_hit + item_hit
    total = header_total + item_total
    return {
        "header_pct": round(100.0 * header_hit / header_total, 1) if header_total else 0.0,
        "items_pct": round(100.0 * item_hit / item_total, 1) if item_total else 0.0,
        "overall_pct": round(100.0 * total_hit / total, 1) if total else 0.0,
        "header_filled": header_hit,
        "header_total": header_total,
        "item_fields_filled": item_hit,
        "item_fields_total": item_total,
        "per_item": per_item,
    }


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
    if not compact_name:
        return False
    if compact_name in compact_source:
        return True
    # OCR이 띄어쓰기·용량단위를 조금 다르게 읽어도 원문에 포함된 핵심 이름은 살린다.
    core = compact_name
    for suffix in ("필름코팅정", "서방정", "연질캡슐", "캡슐", "정", "시럽", "mg", "ml", "g"):
        if core.endswith(suffix) and len(core) > len(suffix) + 1:
            core = core[: -len(suffix)]
            break
    return bool(core) and len(core) >= 2 and core in compact_source


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
        if f"{number}일" in raw_text:
            return True
        # 복약안내 표: "... | 0.50 | 3 | 7"
        return _table_int_present(number, raw_text, role="duration")
    if key == "frequency_per_day":
        if f"{number}회" in raw_text or f"{number}번" in raw_text:
            return True
        return _table_int_present(number, raw_text, role="frequency")
    if key == "times_per_take":
        if (
            f"{number}정" in raw_text
            or f"{number}캡슐" in raw_text
            or f"{number}개" in raw_text
        ):
            return True
        return _table_int_present(number, raw_text, role="times")
    return number in raw_text


def _table_int_present(number: str, raw_text: str, *, role: str) -> bool:
    """표 OCR에서 단위 없이 나온 정수(횟수/일수/투약량)를 허용한다."""
    # 용량(소수) 옆의 정수들: 0.50 | 3 | 7  또는  0.50  3  7
    row_pattern = re.compile(
        r"(?P<dose>\d+(?:\.\d+)?)\s*[|/\s]+\s*(?P<freq>\d+)\s*[|/\s]+\s*(?P<days>\d+)"
    )
    for match in row_pattern.finditer(raw_text):
        if role == "frequency" and match.group("freq") == number:
            return True
        if role == "duration" and match.group("days") == number:
            return True
        if role == "times" and (
            match.group("dose").startswith(number + ".") or match.group("dose") == number
        ):
            return True
    # 단독 정수 칸: | 3 |  /  줄 끝 정수
    if re.search(rf"(?:^|[|\s]){re.escape(number)}(?=$|[|\s])", raw_text, re.MULTILINE):
        return True
    return False
