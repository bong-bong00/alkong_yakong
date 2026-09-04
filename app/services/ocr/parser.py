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
    filtered["items"] = _normalize_table_dosing(filtered["items"])
    filtered["items"] = _merge_duplicate_drugs(filtered["items"])
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
            "   - 처방의약품의 명칭 → drug_name (0.25mg 등 이름에 적힌 용량 포함)\n"
            "   - 약품명에 있는 mg/% → dosage  (예: 0.25mg, 400mg)\n"
            "   - '1 T' '1 C' '1 PKG'는 dosage가 아닙니다. unit=T/C/PKG, times_per_take=1\n"
            "   - 1일 투여횟수 → frequency_per_day (정수, 보통 1~3. 총량 60을 넣지 마세요)\n"
            "   - 총 투약 일수 → duration_days (정수, 예: 60)\n"
            "   - 총량 열은 duration_days로 쓰지 마세요.\n"
            "4) 한 줄에 '0.50 3 7' 또는 '0.50 | 3 | 7'이면\n"
            "   dosage=0.50, frequency_per_day=3, duration_days=7 입니다.\n"
            "4-1) 같은 약이 아침/점심/저녁으로 반복되면 항목을 하나로 합치고\n"
            "   frequency_per_day는 반복 횟수(3)로 하세요.\n"
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


def _normalize_table_dosing(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """보험 처방 표: '1 T'는 용량이 아님. 총량 60을 횟수로 쓰지 않음."""
    result: list[dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        cleaned = dict(item)
        name = str(cleaned.get("drug_name") or "")
        dosage = str(cleaned.get("dosage") or "").strip()
        unit = str(cleaned.get("unit") or "").strip()

        take_match = re.match(
            r"^(\d+(?:\.\d+)?)\s*(T|C|EA|PKG|정|캡슐)$",
            dosage.replace(" ", ""),
            re.IGNORECASE,
        )
        if take_match or unit.upper() in {"T", "C", "EA", "PKG"}:
            if take_match:
                try:
                    cleaned["times_per_take"] = int(float(take_match.group(1)))
                except ValueError:
                    cleaned["times_per_take"] = 1
                cleaned["unit"] = take_match.group(2).upper()
            strength = re.search(
                r"(\d+(?:\.\d+)?)\s*(mg|ml|g|%|밀리그램|밀리그람)",
                name,
                re.IGNORECASE,
            )
            if strength:
                cleaned["dosage"] = strength.group(0).replace(" ", "")
            elif take_match:
                cleaned.pop("dosage", None)

        freq = cleaned.get("frequency_per_day")
        days = cleaned.get("duration_days")
        try:
            freq_n = int(freq) if freq is not None else None
        except (TypeError, ValueError):
            freq_n = None
        # 총량/일수 60을 1일 횟수로 오인
        if freq_n is not None and freq_n >= 10:
            if days is None:
                cleaned["duration_days"] = freq_n
            cleaned["frequency_per_day"] = 1
        result.append(cleaned)
    return result


def _merge_duplicate_drugs(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """아침/점심/저녁으로 반복된 같은 약을 한 줄로 합친다."""
    try:
        from app.services.matching.name_matcher import _medicine_key, extract_strengths
    except Exception:
        return items

    groups: dict[tuple, list[dict[str, Any]]] = {}
    order: list[tuple] = []
    for item in items:
        name = str(item.get("drug_name") or "")
        key = _medicine_key(name)
        strengths = tuple(sorted(extract_strengths(name + " " + str(item.get("dosage") or ""))))
        group_key = (key, strengths)
        if group_key not in groups:
            groups[group_key] = []
            order.append(group_key)
        groups[group_key].append(item)

    merged: list[dict[str, Any]] = []
    for group_key in order:
        rows = groups[group_key]
        base = dict(rows[0])
        if len(rows) > 1:
            slot_n = len(rows)
            freq = base.get("frequency_per_day")
            try:
                freq_n = int(freq) if freq is not None else 1
            except (TypeError, ValueError):
                freq_n = 1
            base["frequency_per_day"] = max(slot_n, freq_n if freq_n < 10 else 1)
        days_vals = []
        for row in rows:
            if row.get("duration_days") is not None:
                try:
                    days_vals.append(int(row["duration_days"]))
                except (TypeError, ValueError):
                    pass
        if days_vals and base.get("duration_days") is None:
            base["duration_days"] = max(days_vals)
        merged.append(base)
    return merged


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


# OCR이 자주 틀리는 글자 → 식약처 공식 표기 (wrong → right)
_OCR_TYPO_FIXES = {
    "프리마라정": "프리마란정",
    "프레베넥액": "프레벨액",
    "프레베넥액0.25%": "프레벨액 0.25%",
    "프레베넥액 0.25%": "프레벨액 0.25%",
    "프레베이액": "프레벨액",
    "프레베이액0.25%": "프레벨액 0.25%",
    "프레베이액 0.25%": "프레벨액 0.25%",
    "휴온스시메티딘정200밀리그람": "휴온스시메티딘정200밀리그램",
    "프리스타서방정": "프리스틱서방정50밀리그램",
    "프리스타 서방정 50mg": "프리스틱서방정50밀리그램",
    "프리스틱 서방정 50mg": "프리스틱서방정50밀리그램",
    "쎄스페이알서방정": "써스펜8시간이알서방정650밀리그램",
    "쎄스페이알서방정 650mg": "써스펜8시간이알서방정650밀리그램",
    "써스펜이알서방정": "써스펜8시간이알서방정650밀리그램",
    "써스펜이알서방정 650mg": "써스펜8시간이알서방정650밀리그램",
    "엑셀론 패취 10": "엑셀론패취10",
    "엑셀론패취 10": "엑셀론패취10",
    "엑셀론 패취 10 9.5mg/24hours": "엑셀론패취10",
    "듀파락 이지 시럽": "듀파락시럽",
    "듀파락이지시럽": "듀파락시럽",
    "듀파락 이지 시럽 15ml/pkg": "듀파락시럽",
    "벤포정": "삐콤정",
}

# OCR에서 자주 바뀌는 한글 한 글자 (교정 후보 검색용)
_OCR_CHAR_SWAPS = (
    ("넥", "벨"),
    ("벨", "넥"),
    ("라", "란"),
    ("란", "라"),
    ("그람", "그램"),
    ("그램", "그람"),
)


def _strip_pack_noise(name: str) -> str:
    """'케토톱엘플라스타 7매/PKG', '코푸시럽 20ml/pkg' → 제품명만."""
    text = str(name or "").strip()
    text = re.sub(r"\s*\d+\s*매\s*/?\s*pkg.*$", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\s*\d+(?:\.\d+)?\s*ml\s*/?\s*pkg.*$", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\s*/\s*pkg.*$", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\s*\d+(?:\.\d+)?\s*mg/24hours?.*$", "", text, flags=re.IGNORECASE)
    return text.strip(" ,-/")


def _correct_one_drug_name(name: str) -> str:
    """OCR 약명을 식약처 공식 약품명에 맞게 교정한다."""
    raw = _strip_pack_noise((name or "").strip())
    if not raw:
        return (name or "").strip()
    compact_raw = _compact(raw)

    # 1) 알려진 OCR 오타 표 (긴 키 우선 — '프레베넥액 0.25%'가 '프레베넥액'에 먹히지 않게)
    for wrong, right in sorted(
        _OCR_TYPO_FIXES.items(),
        key=lambda item: len(_compact(item[0])),
        reverse=True,
    ):
        wrong_c = _compact(wrong)
        if compact_raw == wrong_c or compact_raw.startswith(wrong_c):
            return right

    try:
        from app.services.matching.name_matcher import match_medicine_name
    except Exception:
        return raw

    lexicon = _ocr_name_lexicon(raw)
    if not lexicon:
        return raw
    match = match_medicine_name(raw, lexicon)
    # 공식 사전과 0.90 이상/키 동일하면 공식명으로 교정
    if match.matched_name:
        # 괄호 성분 등은 짧은 표시명으로 정리
        return _short_official_label(match.matched_name, raw)
    return raw


def _short_official_label(official: str, ocr_raw: str) -> str:
    """'프레벨액0.25%(프레드니카르베이트)' → OCR에 %가 있으면 용량 유지한 짧은 이름."""
    base = _clean_drug_label(official)
    # 괄호 앞까지만
    base = re.split(r"[（(]", base, maxsplit=1)[0].strip()
    if re.search(r"\d+(?:\.\d+)?\s*%", ocr_raw) and "%" not in base:
        # OCR에 농도가 있으면 공식명에 농도 붙이기
        m = re.search(r"(\d+(?:\.\d+)?\s*%)", official) or re.search(
            r"(\d+(?:\.\d+)?\s*%)", ocr_raw
        )
        if m and m.group(1) not in base:
            return f"{base}" if re.search(r"\d+(?:\.\d+)?%", base) else base
    return base


def _confusable_queries(name: str) -> list[str]:
    """한 글자 OCR 혼동을 바꿔 식약처 검색어를 만든다."""
    raw = (name or "").strip()
    out: list[str] = []
    seen: set[str] = set()

    def _add(value: str) -> None:
        text = (value or "").strip()
        if text and text not in seen:
            seen.add(text)
            out.append(text)

    _add(raw)
    for a, b in _OCR_CHAR_SWAPS:
        if a in raw:
            _add(raw.replace(a, b, 1))
    return out


def _ocr_name_lexicon(raw: str) -> list[str]:
    """교정용 공식 약품명 사전(허가DB·식약처 API·로컬 medicines)."""
    lexicon: list[str] = []
    seen: set[str] = set()

    def _add(label: str) -> None:
        text = _clean_drug_label(label)
        if text and text not in seen:
            # OCR 오타 문자열 자체는 후보에서 제외
            if _compact(text) == _compact(raw):
                return
            seen.add(text)
            lexicon.append(text)

    # 시화병원 봉투 등에서 확인된 공식 표기
    for known in (
        "프리마란정",
        "아디팜정",
        "모사피아정",
        "프로맥정",
        "니자액스캡슐150mg",
        "휴온스시메티딘정200밀리그램",
        "프레벨액",
        "프레벨액 0.25%",
        "프레벨액0.25%",
        "프리스틱서방정50밀리그램",
        "써스펜8시간이알서방정650밀리그램",
        "엑셀론패취10",
        "케토톱엘플라스타",
        "코푸시럽에스",
        "듀파락시럽",
        "삐콤정",
    ):
        _add(known)

    compact = _compact(raw)
    core = re.sub(r"\d+(?:\.\d+)?(?:mg|ml|g|%|밀리그람|밀리그램)", "", compact)
    prefixes = [raw[:2], raw[:3], core[:2], core[:3], core[:4]]

    # 로컬 허가 미러 DB
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

    # 식약처 허가 API 실시간 (DB가 비어 있을 때) + 혼동 글자 검색
    try:
        from app.services.mfds_drug_permission.client import (
            extract_items,
            fetch_permission_list_page,
        )

        search_terms = list(prefixes)
        for variant in _confusable_queries(raw):
            search_terms.append(variant)
            hangul = re.sub(r"[^가-힣]", "", variant)
            if len(hangul) >= 3:
                search_terms.append(hangul[:3])
            if len(hangul) >= 4:
                search_terms.append(hangul[:4])
        for term in search_terms:
            token = str(term or "").strip()
            if len(token) < 2:
                continue
            try:
                payload = fetch_permission_list_page(
                    page_no=1,
                    num_of_rows=8,
                    item_name=token,
                )
                for item in extract_items(payload):
                    _add(str(item.get("ITEM_NAME") or ""))
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
                rows = conn.execute(
                    "SELECT product_name FROM medicines "
                    "WHERE product_name LIKE ? "
                    "AND (medicine_code IS NULL OR medicine_code NOT LIKE 'OCR-%') "
                    "LIMIT 20",
                    (f"%{token}%",),
                ).fetchall()
                for row in rows:
                    _add(str(row[0] or ""))
        finally:
            conn.close()
    except Exception:
        pass

    return lexicon


def _strip_non_drug_markers(name: str) -> str:
    """처방 표 기호·구분코드를 약 이름에서 제거.

    비)다이크로지정, 급)타이레놀, 원내)세파클러 처럼
    '한 글자/짧은 말 + 괄호·점' 형태는 약 이름이 아님.
    비타민·비오플처럼 '비'로 시작하는 실제 약명은 그대로 둔다.
    """
    text = str(name or "").strip()
    delim = r"[)\]\}>:：.\-/|·,]"
    words = (
        "비급여",
        "급여대상",
        "급여약",
        "비급여약",
        "본인부담",
        "산정특례",
        "원내처방",
        "원외처방",
        "원내약",
        "원외약",
        "의료급여",
        "보훈급여",
        "차상위",
        "전액본인",
        "100분의100",
        "100/100",
        "비급여",
        "급여",
        "비급",
        "원내",
        "원외",
        "보훈",
        "향정",
        "마약",
        "한약",
        "건보",
        "자보",
        "산재",
    )
    # 한 글자 구분 코드: 비) 급) 원) 보) 향) 마) 산) 자)
    code_letters = "비급원보향마산자내외특"

    for _ in range(5):
        prev = text
        text = re.sub(r"^(?:" + "|".join(words) + r")\s*", "", text)
        text = re.sub(rf"^[{code_letters}]\s*{delim}\s*", "", text)
        text = re.sub(rf"^{delim}+\s*", "", text)
        # 선두 기호: ★ ☆ ● ○ ◎ ■ □ △ ▲ ※
        text = re.sub(r"^[\s★☆●○◎■□△▲※*]+", "", text)
        # 표준코드처럼 이름 앞에 붙은 숫자 코드 (8자리 이상)
        text = re.sub(r"^\d{8,}\s*", "", text)
        if text == prev:
            break
    return text.strip(" -/|")


def _clean_drug_label(name: str) -> str:
    """'비)다이크로지정 (이뇨제)' → '다이크로지정'."""
    text = _strip_non_drug_markers(str(name or "").strip())
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
