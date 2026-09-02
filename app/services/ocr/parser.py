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
    """Gemini 구조화 우선, 실패(할당량 등) 시 휴리스틱 구조화."""
    text = (raw_text or "").strip()
    if not text:
        return None

    parsed = _parse_with_gemini(text)
    parser_engine = "gemini-json"
    if not parsed:
        parsed = _parse_with_heuristic(text)
        parser_engine = "heuristic"

    if not parsed or not parsed.get("items"):
        return None

    filtered = filter_to_source(parsed, text)
    if not filtered.get("items"):
        # 이름 교정 전 단계의 휴리스틱 결과는 원문 토큰이 잘려 있을 수 있어
        # 필터가 전부 지우면 휴리스틱 원본을 한 번 더 살린다.
        if parser_engine == "heuristic":
            filtered = enrich_dosing_from_raw(parsed, text)
            filtered = correct_drug_names(filtered)
        else:
            return None
    else:
        filtered = enrich_dosing_from_raw(filtered, text)
        filtered = correct_drug_names(filtered)

    if not filtered.get("items"):
        return None
    filtered["field_coverage"] = measure_field_coverage(filtered)
    filtered["parser_engine"] = parser_engine
    return filtered


def _parse_with_gemini(text: str) -> dict[str, Any] | None:
    if not GEMINI_API_KEY:
        return None
    try:
        from google import genai

        prompt = (
            "아래 처방전/복약안내 원문만 근거로 JSON 구조화하세요.\n"
            "규칙:\n"
            "1) 원문에 없는 약 이름·용량·횟수·기간을 추측하지 마세요.\n"
            "2) 확인되지 않는 항목은 생략하세요.\n"
            "3) 표/줄 형식이면 열을 이렇게 매핑하세요.\n"
            "   - 약품명 → drug_name\n"
            "   - 1회 투약량(0.50 등) → dosage\n"
            "   - 1일 투여횟수 → frequency_per_day (정수)\n"
            "   - 투약 일수/N일분 → duration_days (정수)  ※ 반드시 채우세요\n"
            "4) 한 줄에 '0.50 3 7' 또는 '0.50 | 3 | 7'이면\n"
            "   dosage=0.50, frequency_per_day=3, duration_days=7 입니다.\n"
            "5) 복용법/효능 설명 문장은 easy_explanation에 넣으세요.\n"
            "6) prescribed_date는 YYYY-MM-DD로 정규화하세요.\n"
            "7) hospital_name은 병원/의원명, pharmacy_name은 약국명 또는 조제약사명.\n\n"
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
        return parsed
    except Exception:
        return None


def _parse_with_heuristic(text: str) -> dict[str, Any] | None:
    """Gemini 없이 CLOVA 원문 등에서 약 줄을 규칙으로 뽑는다."""
    if not text.strip():
        return None

    hospital = None
    pharmacy = None
    prescribed = None
    for pattern, key in (
        (r"(미래의원|[\w가-힣]+의원|[\w가-힣]+병원)", "hospital"),
        (r"(?:조제약\s*사|약사)\s*:?\s*([가-힣]{2,4})", "pharmacy"),
        (r"(?:조제\s*일\s*자|처방일자)\s*:?\s*(\d{4}[.-]\d{1,2}[.-]\d{1,2})", "date"),
        (r"(\d{4}-\d{2}-\d{2})", "date"),
    ):
        match = re.search(pattern, text)
        if not match:
            continue
        value = match.group(1) if match.lastindex else match.group(0)
        if key == "hospital" and not hospital:
            hospital = value
        elif key == "pharmacy" and not pharmacy:
            pharmacy = value
        elif key == "date" and not prescribed:
            prescribed = value.replace(".", "-")

    items: list[dict[str, Any]] = []
    # 약이름 + 용량 + 횟수 + (일수)
    row_re = re.compile(
        r"([가-힣A-Za-z][가-힣A-Za-z0-9.%]{1,40}(?:정|캡슐|액|시럽|산|주))"
        r"(?:\s*\([^)]*\))?"
        r".{0,80}?"
        r"(\d+(?:\.\d+)?)"
        r"\s*[|/\s]+\s*"
        r"(\d+)"
        r"(?:\s*[|/\s]+\s*(\d+))?",
        re.DOTALL,
    )
    seen: set[str] = set()
    for match in row_re.finditer(text):
        name = _clean_drug_label(match.group(1))
        if not name or name in seen:
            continue
        if name in {"투여횟수", "투약량", "투약일수", "약품명"}:
            continue
        seen.add(name)
        item: dict[str, Any] = {
            "drug_name": name,
            "dosage": match.group(2),
            "frequency_per_day": int(match.group(3)),
        }
        if match.group(4):
            item["duration_days"] = int(match.group(4))
        items.append(item)

    if not items:
        return None
    result: dict[str, Any] = {"items": items}
    if hospital:
        result["hospital_name"] = hospital
    if pharmacy:
        result["pharmacy_name"] = pharmacy
    if prescribed:
        result["prescribed_date"] = prescribed
    return result


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
        name = _clean_drug_label(str(item.get("drug_name") or "").strip())
        if not name or not _name_in_source(name, compact_source):
            # 괄호 설명 붙은 이름도 원문 핵심만으로 한 번 더 검사
            if not name or not _name_in_source(name.split("(")[0].strip(), compact_source):
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


def enrich_dosing_from_raw(structured: dict[str, Any], raw_text: str) -> dict[str, Any]:
    """구조화에서 빠진 용량·횟수·일수를 원문 표 숫자로 채운다."""
    source = raw_text or ""
    items: list[dict[str, Any]] = []
    for item in structured.get("items") or []:
        if not isinstance(item, dict):
            continue
        cleaned = dict(item)
        name = str(cleaned.get("drug_name") or "")
        dosing = _dosing_near_name(name, source)
        if dosing:
            if not cleaned.get("dosage") and dosing.get("dosage"):
                cleaned["dosage"] = dosing["dosage"]
            if cleaned.get("frequency_per_day") is None and dosing.get("frequency_per_day") is not None:
                cleaned["frequency_per_day"] = dosing["frequency_per_day"]
            if cleaned.get("duration_days") is None and dosing.get("duration_days") is not None:
                cleaned["duration_days"] = dosing["duration_days"]
        items.append(cleaned)
    result = dict(structured)
    result["items"] = items
    return result


def correct_drug_names(structured: dict[str, Any]) -> dict[str, Any]:
    """OCR 약이름 오타를 허가정보·유사도 매칭으로 공식명에 가깝게 고친다."""
    items: list[dict[str, Any]] = []
    for item in structured.get("items") or []:
        if not isinstance(item, dict):
            continue
        cleaned = dict(item)
        name = _clean_drug_label(str(cleaned.get("drug_name") or "").strip())
        cleaned["drug_name"] = name
        if name:
            fixed = _correct_one_drug_name(name)
            if fixed:
                cleaned["drug_name"] = fixed
                if fixed != name:
                    cleaned["ocr_drug_name_raw"] = name
        items.append(cleaned)
    result = dict(structured)
    result["items"] = items
    return result


def _dosing_near_name(drug_name: str, raw_text: str) -> dict[str, Any]:
    """약이름이 있는 줄(또는 바로 다음 줄)에서만 투약량·횟수·일수를 찾는다."""
    name = (drug_name or "").strip()
    if not name or not raw_text:
        return {}
    core = _compact(name)
    for suffix in ("필름코팅정", "서방정", "연질캡슐", "캡슐", "정", "시럽", "액"):
        if core.endswith(suffix) and len(core) > len(suffix) + 1:
            core = core[: -len(suffix)]
            break
    if len(core) < 2:
        return {}

    lines = raw_text.splitlines()
    window = ""
    for index, line in enumerate(lines):
        compact_line = _compact(line)
        if core[: min(4, len(core))] in compact_line or _compact(name)[:6] in compact_line:
            parts = [line]
            if index + 1 < len(lines):
                parts.append(lines[index + 1])
            window = " ".join(parts)
            break
    if not window:
        return {}

    # 반드시 약 근처 줄에서만: 0.50 | 3 | 7
    triple = re.search(
        r"(?P<dose>\d+(?:\.\d+)?)\s*[|/\s]+\s*(?P<freq>\d+)\s*[|/\s]+\s*(?P<days>\d+)",
        window,
    )
    if triple:
        return {
            "dosage": triple.group("dose"),
            "frequency_per_day": int(triple.group("freq")),
            "duration_days": int(triple.group("days")),
        }
    pair = re.search(
        r"(?P<dose>\d+(?:\.\d+)?)\s*[|/\s]+\s*(?P<freq>\d+)\b",
        window,
    )
    result: dict[str, Any] = {}
    if pair:
        result["dosage"] = pair.group("dose")
        result["frequency_per_day"] = int(pair.group("freq"))
    # 전체 원문이 아니라 이 약 줄에서만 '7일분' 등을 본다 (헤더 '1일' 오인 방지)
    days = re.search(r"(?<!\d)(\d{1,3})\s*일분", window)
    if days:
        result["duration_days"] = int(days.group(1))
    return result


# 복약안내 OCR에서 반복되는 한두 글자 오타
_OCR_TYPO_FIXES = {
    "프리마란정": "프리마라정",
    "프레벨액": "프레베넥액",
    "프레벨렉액": "프레베넥액",
    "프레벨액0.25%": "프레베넥액 0.25%",
    "휴온스시메티딘정200밀리그램": "휴온스시메티딘정200밀리그람",
}


def _correct_one_drug_name(name: str) -> str:
    raw = (name or "").strip()
    if not raw:
        return raw
    compact_raw = _compact(raw)
    for wrong, right in _OCR_TYPO_FIXES.items():
        if compact_raw == _compact(wrong) or compact_raw.startswith(_compact(wrong)):
            return right

    try:
        from app.services.matching.name_matcher import match_medicine_name
    except Exception:
        return raw

    lexicon = _ocr_name_lexicon(raw)
    if not lexicon:
        return raw
    match = match_medicine_name(raw, lexicon)
    # AUTO_ACCEPT(0.90) 이상만 조용히 교정. 미만은 OCR 원문 유지.
    if match.matched_name:
        return match.matched_name
    return raw


def _ocr_name_lexicon(raw: str) -> list[str]:
    """허가DB가 없거나 비어도 로컬 medicines + 흔한 OCR 교정 후보로 사전을 만든다."""
    lexicon: list[str] = []
    seen: set[str] = set()

    def _add(label: str) -> None:
        text = _clean_drug_label(label)
        if text and text not in seen:
            seen.add(text)
            lexicon.append(text)

    # 이 프로젝트 복약안내 샘플에서 자주 틀리는 이름
    for known in (
        "프리마라정",
        "아디팜정",
        "휴온스시메티딘정200밀리그람",
        "휴온스시메티딘정200밀리그램",
        "프레베넥액",
        "프레베넥액 0.25%",
    ):
        _add(known)

    compact = _compact(raw)
    core = re.sub(r"\d+(?:\.\d+)?(?:mg|ml|g|%|밀리그람|밀리그램)", "", compact)
    prefixes = [raw[:2], raw[:3], core[:2], core[:3], core[:4]]
    try:
        from app.services.mfds_drug_permission.db import search_permission_names

        for prefix in prefixes:
            token = str(prefix or "").strip()
            if len(token) < 2:
                continue
            try:
                for hit in search_permission_names(token, limit=12):
                    _add(hit)
            except Exception:
                continue
    except Exception:
        pass

    try:
        from app.database import get_connection

        conn = get_connection()
        try:
            for prefix in prefixes:
                token = str(prefix or "").strip()
                if len(token) < 2:
                    continue
                # OCR 임시로 넣어진 오타 이름(OCR-…)은 교정 사전에서 제외
                rows = conn.execute(
                    "SELECT product_name FROM medicines "
                    "WHERE product_name LIKE ? "
                    "AND (medicine_code IS NULL OR medicine_code NOT LIKE 'OCR-%') "
                    "LIMIT 20",
                    (f"%{token}%",),
                ).fetchall()
                for row in rows:
                    label = str(row[0] or "")
                    # 지금 OCR이 읽은 오타 문자열 자체는 후보에서 빼 공식명 쪽으로 유도
                    if _compact(label) == _compact(raw):
                        continue
                    _add(label)
        finally:
            conn.close()
    except Exception:
        pass

    return lexicon


def _clean_drug_label(name: str) -> str:
    """'프리마라정 (알러지질환약)' → '프리마라정'."""
    text = str(name or "").strip()
    text = re.sub(r"\s*\([^)]*\)\s*", " ", text)
    text = re.sub(r"\s*\[[^\]]*\]\s*", " ", text)
    return re.sub(r"\s+", " ", text).strip()


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
    """표 OCR에서 단위 없이 나온 정수(횟수·일수)를 허용한다. 단독 '1' 같은 느슨한 일치는 쓰지 않는다."""
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
    # 횟수만 있는 줄: 0.50 | 3  (일수 없음)
    if role == "frequency":
        pair = re.compile(
            r"(?P<dose>\d+(?:\.\d+)?)\s*[|/\s]+\s*(?P<freq>\d+)(?!\s*[|/\s]+\s*\d)"
        )
        for match in pair.finditer(raw_text):
            if match.group("freq") == number:
                return True
    return False
