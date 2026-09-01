"""Suggestions for the guided pharmacist chat (Asan-style autocomplete)."""

from __future__ import annotations

import re
import time

from app.database import get_connection
from app.services.external_api_service import search_drug_info_by_name
from app.services.matching.chosung import is_chosung_query, to_chosung
from app.services.mfds_drug_permission.db import search_permission_names


FAQ_SUGGESTIONS = (
    "지금 먹을 약",
    "이 약 설명",
    "같이 먹으면",
    "안 먹었을 때",
)

RELATED_FAQ = (
    "이 약 설명",
    "같이 먹으면",
    "안 먹었을 때",
)

# 식약처에서 확인한 흔한 제품명. API가 비거나 느릴 때 접두 자동완성용.
FALLBACK_OFFICIAL_NAMES = (
    "타이레놀정500밀리그램",
    "타이레놀8시간이알서방정",
    "부루펜정200밀리그램(이부프로펜)",
    "게보린정",
    "아스피린장용정",
)

# 어르신 대충 입력 → 검색 키워드 / FAQ.
# triggers는 긴 것 우선 매칭. search는 허가정보·e약은요 조회용.
SENIOR_HINT_GROUPS: tuple[dict[str, tuple[str, ...]], ...] = (
    {
        "triggers": ("타이래", "타일레", "타이레", "타이", "ㅌㅇㄹㄴ", "ㅌㄹㄴ", "ㅌㄹ"),
        "search": ("타이레놀",),
        "faqs": (),
    },
    {
        "triggers": ("부르펜", "부루펜", "부루", "ㅂㄹㅍ", "ㅂㄹ"),
        "search": ("부루펜",),
        "faqs": (),
    },
    {
        "triggers": ("게보링", "게보린", "게보", "ㄱㅂㄹ", "ㄱㅂ"),
        "search": ("게보린",),
        "faqs": (),
    },
    {
        "triggers": ("아스피린", "아스피", "ㅇㅅㅍㄹ", "ㅇㅅㅍ"),
        "search": ("아스피린",),
        "faqs": (),
    },
    {
        "triggers": ("프리마란", "프리마", "ㅍㄹㅁㄹ", "ㅍㄹㅁ"),
        "search": ("프리마란",),
        "faqs": (),
    },
    {
        "triggers": ("열올라", "열나", "해열", "열난"),
        "search": ("타이레놀",),
        "faqs": ("이 약 설명",),
    },
    {
        "triggers": ("열",),
        "search": ("타이레놀",),
        "faqs": ("이 약 설명",),
    },
    {
        "triggers": ("머리아픈", "머리아", "두통", "골치"),
        "search": ("게보린", "타이레놀"),
        "faqs": ("이 약 설명",),
    },
    {
        "triggers": ("몸살", "콧물", "감기"),
        "search": ("타이레놀콜드", "타이레놀", "게보린"),
        "faqs": ("이 약 설명",),
    },
    {
        "triggers": ("속안좋", "체한", "배아", "소화"),
        "search": (),
        "faqs": ("이 약 설명", "같이 먹으면"),
    },
    {
        "triggers": ("허리아", "무릎", "관절", "허리"),
        "search": ("부루펜",),
        "faqs": ("이 약 설명",),
    },
    {
        "triggers": ("혈압",),
        "search": (),
        "faqs": ("같이 먹으면", "이 약 설명"),
    },
    {
        "triggers": ("당뇨",),
        "search": (),
        "faqs": ("같이 먹으면", "이 약 설명"),
    },
    {
        "triggers": ("언제먹", "밥전", "식후", "몇알", "하루몇"),
        "search": (),
        "faqs": ("지금 먹을 약", "이 약 설명"),
    },
    {
        "triggers": ("같이먹", "겹쳐", "같이"),
        "search": (),
        "faqs": ("같이 먹으면",),
    },
    {
        "triggers": ("어제안", "안먹", "깜빡", "잊었"),
        "search": (),
        "faqs": ("안 먹었을 때",),
    },
    {
        "triggers": ("부작용", "어지러", "졸려", "속이"),
        "search": (),
        "faqs": ("이 약 설명", "안 먹었을 때"),
    },
    {
        "triggers": ("이거뭐", "효과있", "저약", "뭐야"),
        "search": (),
        "faqs": ("이 약 설명",),
    },
    {
        "triggers": ("술하고", "술먹"),
        "search": (),
        "faqs": ("같이 먹으면",),
    },
    {
        "triggers": ("먹어도돼", "두알"),
        "search": (),
        "faqs": ("이 약 설명", "같이 먹으면"),
    },
)

_CACHE_TTL_SECONDS = 60.0
_official_cache: dict[str, tuple[float, list[str]]] = {}


def get_chat_suggestions(query: str = "", user_id: str | None = None) -> list[dict[str, str]]:
    needle = _compact(query)
    if not needle:
        items = [{"label": label, "type": "faq"} for label in FAQ_SUGGESTIONS]
        items.extend(_today_medicines(user_id, ""))
        return _unique(items)[:20]

    items: list[dict[str, str]] = []
    hint = _match_senior_hint(needle)

    # 1순위: 허가정보 DB / 힌트 검색어 / e약은요 / 초성
    search_queries: list[str] = []
    if hint:
        search_queries.extend(hint.get("search") or ())
    raw_query = query.strip()
    if is_chosung_query(raw_query) or len(needle) >= 2:
        search_queries.append(raw_query)

    seen_search: set[str] = set()
    for search_query in search_queries:
        key = _compact(search_query)
        if not key or key in seen_search:
            continue
        seen_search.add(key)
        items.extend(
            {"label": name, "type": "medicine"}
            for name in _official_names(search_query)
        )

    items.extend(_today_medicines(user_id, needle))
    items.extend(_local_medicines(needle))

    seen_names = {_compact(item["label"]) for item in items}
    first_name = next((item["label"] for item in items if item["type"] != "faq"), None)
    if first_name:
        short = _short_name(first_name)
        for faq in RELATED_FAQ:
            label = f"{short} {faq}"
            if _compact(label) not in seen_names:
                items.append({"label": label, "type": "faq"})
                seen_names.add(_compact(label))

    if hint:
        for faq in hint.get("faqs") or ():
            if _compact(faq) not in seen_names:
                items.append({"label": faq, "type": "faq"})
                seen_names.add(_compact(faq))

    for label in FAQ_SUGGESTIONS:
        if needle in _compact(label) or _compact(label) in needle:
            if _compact(label) not in seen_names:
                items.append({"label": label, "type": "faq"})
                seen_names.add(_compact(label))

    return _unique(items)[:12]


def _match_senior_hint(needle: str) -> dict[str, tuple[str, ...]] | None:
    best: dict[str, tuple[str, ...]] | None = None
    best_len = -1
    for group in SENIOR_HINT_GROUPS:
        for trigger in group["triggers"]:
            if not _trigger_hit(needle, trigger):
                continue
            if len(trigger) > best_len:
                best = group
                best_len = len(trigger)
    return best


def _trigger_hit(needle: str, trigger: str) -> bool:
    if not needle or not trigger:
        return False
    if len(trigger) == 1:
        return needle == trigger or needle.startswith(trigger)
    return trigger in needle or needle in trigger


def _today_medicines(user_id: str | None, needle: str) -> list[dict[str, str]]:
    if not user_id:
        return []
    conn = get_connection()
    try:
        rows = conn.execute(
            """
            SELECT DISTINCT m.product_name
            FROM user_medicines um
            JOIN medicines m ON m.medicine_code = um.medicine_code
            WHERE um.user_id = ? AND m.product_name IS NOT NULL
            """,
            (user_id,),
        ).fetchall()
    finally:
        conn.close()
    return _filter_names(rows, needle, "today_medicine")


def _local_medicines(needle: str) -> list[dict[str, str]]:
    conn = get_connection()
    try:
        rows = conn.execute(
            "SELECT product_name FROM medicines WHERE product_name IS NOT NULL"
        ).fetchall()
    finally:
        conn.close()
    return _filter_names(rows, needle, "medicine")


def _filter_names(rows, needle: str, item_type: str) -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    for row in rows:
        label = str(row["product_name"] or "").strip()
        if label and (not needle or needle in _compact(label)):
            items.append({"label": label, "type": item_type})
    return items


def _official_names(query: str) -> list[str]:
    raw = (query or "").strip()
    if not raw:
        return []

    # 초성 전용 검색 (ㅌㄹㄴ 등)
    if is_chosung_query(raw):
        chosung = "".join(raw.split())
        cache_key = f"chosung:{chosung}"
        cached = _official_cache.get(cache_key)
        now = time.monotonic()
        if cached and now - cached[0] < _CACHE_TTL_SECONDS:
            return cached[1]
        names: list[str] = []
        try:
            names.extend(search_permission_names(raw, limit=10))
        except Exception:
            pass
        for name in FALLBACK_OFFICIAL_NAMES:
            if to_chosung(name).startswith(chosung) and name not in names:
                names.append(name)
        unique_names = list(dict.fromkeys(names))
        _official_cache[cache_key] = (now, unique_names)
        return unique_names

    needle = _compact(raw)
    cached = _official_cache.get(needle)
    now = time.monotonic()
    if cached and now - cached[0] < _CACHE_TTL_SECONDS:
        return cached[1]

    names = []
    try:
        for label in search_permission_names(raw, limit=10):
            if label and (
                _matches_prefix(label, needle) or needle in _compact(label)
            ):
                names.append(label)
    except Exception:
        pass

    try:
        result = search_drug_info_by_name(raw, num_of_rows=8)
        for item in result.get("items") or []:
            label = str(item.get("product_name") or item.get("medicine_name") or "").strip()
            if (
                label
                and (_matches_prefix(label, needle) or needle in _compact(label))
                and label not in names
            ):
                names.append(label)
    except Exception:
        pass

    for name in FALLBACK_OFFICIAL_NAMES:
        if (
            _matches_prefix(name, needle) or needle in _compact(name)
        ) and name not in names:
            names.append(name)

    names.sort(key=lambda name: _rank_name(name, needle))
    unique_names = list(dict.fromkeys(names))
    _official_cache[needle] = (now, unique_names)
    return unique_names


def _matches_prefix(name: str, needle: str) -> bool:
    """연관어는 접두 일치만. 성분명 한가운데 우연 일치는 제외."""
    compact = re.sub(r"\([^)]*\)", "", _compact(name))
    short = _compact(_short_name(name))
    return compact.startswith(needle) or short.startswith(needle)


def _rank_name(name: str, needle: str) -> tuple:
    compact = re.sub(r"\([^)]*\)", "", _compact(name))
    short = _compact(_short_name(name))
    preferred = name in FALLBACK_OFFICIAL_NAMES
    starts = compact.startswith(needle) or short.startswith(needle)
    return (0 if starts else 1, 0 if preferred else 1, len(short), len(compact), name)


def _short_name(name: str) -> str:
    text = re.sub(r"\([^)]*\)", "", _compact(name))
    text = re.sub(r"\d+(?:\.\d+)?(?:mg|ml|g|밀리그램|밀리그람)", "", text)
    for suffix in ("필름코팅정", "서방정", "연질캡슐", "캡슐", "정", "시럽"):
        if text.endswith(suffix):
            text = text[: -len(suffix)]
            break
    return text or name.strip()


def _compact(value: str) -> str:
    return "".join(str(value or "").casefold().split())


def _unique(items: list[dict[str, str]]) -> list[dict[str, str]]:
    unique: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in items:
        label = item["label"]
        if label in seen:
            continue
        seen.add(label)
        unique.append(item)
    return unique
