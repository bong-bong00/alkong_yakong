"""Match OCR medicine names against the verified local lexicon."""

from __future__ import annotations

from dataclasses import dataclass
from difflib import SequenceMatcher
import re


AUTO_ACCEPT = 0.90
SIMILAR_ACCEPT = 0.80  # 미매칭 시 한두 글자 OCR 오타 추론 (짓↔짙 등)
CANDIDATE_MIN = 0.75


@dataclass(frozen=True)
class MatchResult:
    query: str
    matched_name: str | None
    score: float
    method: str
    candidates: tuple[tuple[str, float], ...]


def _normalize(value: str) -> str:
    return "".join(str(value or "").lower().split())


def _medicine_key(value: str) -> str:
    normalized = _normalize(value)
    normalized = re.sub(r"\([^)]*\)", "", normalized)
    normalized = re.sub(r"\[[^\]]*\]", "", normalized)
    normalized = re.sub(r"[·]", "", normalized)
    normalized = re.sub(
        r"\d+(?:\.\d+)?(?:mg|ml|g|%|밀리그램|밀리그람)",
        "",
        normalized,
    )
    for dosage_form in (
        "필름코팅정",
        "이알서방정",
        "서방정",
        "연질캡슐",
        "플라스타",
        "패취",
        "패치",
        "캡슐",
        "시럽",
        "연고",
        "크림",
        "액",
        "정",
    ):
        if normalized.endswith(dosage_form):
            normalized = normalized[: -len(dosage_form)]
            break
    return normalized


def extract_strengths(value: str) -> set[float]:
    """이름 안 용량 숫자(mg/% 등) 추출."""
    text = str(value or "").casefold()
    nums: set[float] = set()
    for match in re.finditer(
        r"(\d+(?:\.\d+)?)\s*(?:mg|ml|g|%|밀리그램|밀리그람)",
        text,
    ):
        try:
            nums.add(float(match.group(1)))
        except ValueError:
            continue
    # 피엠에스플루옥세틴캡슐10 / 토핀정25 형태
    for match in re.finditer(r"(?:정|캡슐|액)\s*(\d+(?:\.\d+)?)", text):
        try:
            nums.add(float(match.group(1)))
        except ValueError:
            continue
    return nums


def _dosage_form(value: str) -> str | None:
    text = _normalize(value)
    for form in (
        "필름코팅정",
        "이알서방정",
        "서방정",
        "연질캡슐",
        "플라스타",
        "패취",
        "패치",
        "캡슐",
        "시럽",
        "연고",
        "크림",
        "액",
        "정",
    ):
        if form in text:
            return "패취" if form == "패치" else form
    return None


def forms_compatible(query: str, official: str) -> bool:
    """시럽↔정 처럼 제형이 뚜렷이 다르면 거부."""
    q_form = _dosage_form(query)
    o_form = _dosage_form(official)
    if not q_form or not o_form:
        return True
    if q_form == o_form:
        return True
    tablet = {"정", "필름코팅정", "서방정", "이알서방정"}
    if q_form in tablet and o_form in tablet:
        return True
    return False


def strengths_compatible(
    query: str,
    official: str,
    *,
    dosage_hint: str | float | None = None,
) -> bool:
    """OCR/힌트 용량과 공식명 용량이 충돌하면 False (250≠500)."""
    official_nums = extract_strengths(official)
    query_nums = extract_strengths(query)
    if dosage_hint is not None and str(dosage_hint).strip():
        hint_text = str(dosage_hint)
        # "250" / "250mg" / "500, 10"
        for part in re.split(r"[,/]", hint_text):
            found = extract_strengths(part if re.search(r"[a-z%밀리]", part.casefold()) else f"{part}mg")
            if not found:
                try:
                    query_nums.add(float(re.search(r"\d+(?:\.\d+)?", part).group(0)))  # type: ignore[union-attr]
                except (AttributeError, ValueError, TypeError):
                    pass
            else:
                query_nums |= found
    if not query_nums or not official_nums:
        return True
    # 교집합이 있으면 호환. OCR 250 vs 공식 500만 있으면 거부.
    return bool(query_nums & official_nums)


def _display_core(value: str) -> str:
    """비교용: 괄호 성분·용량 단위를 뺀 제품 핵심명."""
    text = re.sub(r"\([^)]*\)", "", str(value or ""))
    text = re.sub(r"\[[^\]]*\]", "", text)
    return _normalize(text)


def _rank_candidates(
    query: str,
    lexicon: list[str],
    *,
    dosage_hint: str | float | None = None,
) -> list[tuple[str, float]]:
    medicine_key = _medicine_key(query)
    q_core = _display_core(query)
    ranked: list[tuple[str, float]] = []
    for name in lexicon:
        if not strengths_compatible(query, name, dosage_hint=dosage_hint):
            continue
        if not forms_compatible(query, name):
            continue
        n_core = _display_core(name)
        n_key = _medicine_key(name)
        full = SequenceMatcher(None, q_core, n_core).ratio()
        key = (
            SequenceMatcher(None, medicine_key, n_key).ratio()
            if medicine_key and n_key
            else 0.0
        )
        # 접두 포함(잘린 OCR명): 피엠에스플루옥세틴캡슐10 ⊂ 공식명
        prefix_bonus = 0.0
        if len(q_core) >= 6 and (n_core.startswith(q_core) or q_core in n_core):
            prefix_bonus = 0.12
        elif len(medicine_key) >= 4 and n_key.startswith(medicine_key):
            prefix_bonus = 0.10
        score = min(1.0, max(full, key) + prefix_bonus)
        ranked.append((name, score))
    ranked.sort(key=lambda item: item[1], reverse=True)
    return ranked


def match_medicine_name(
    query: str,
    lexicon: list[str],
    *,
    dosage_hint: str | float | None = None,
    similar: bool = False,
) -> MatchResult:
    """similar=True 이면 미매칭용 유사 추론(SIMILAR_ACCEPT)까지 허용."""
    raw = (query or "").strip()
    if not raw or not lexicon:
        return MatchResult(raw, None, 0.0, "none", ())

    usable = [
        name
        for name in lexicon
        if strengths_compatible(raw, name, dosage_hint=dosage_hint)
        and forms_compatible(raw, name)
    ]
    if not usable:
        return MatchResult(raw, None, 0.0, "none", ())

    for name in usable:
        if name == raw:
            return MatchResult(raw, name, 1.0, "exact", ((name, 1.0),))

    normalized = _normalize(raw)
    for name in usable:
        if _normalize(name) == normalized:
            return MatchResult(raw, name, 0.99, "normalized", ((name, 0.99),))

    medicine_key = _medicine_key(raw)
    key_hits = [
        name
        for name in usable
        if medicine_key and _medicine_key(name) == medicine_key
    ]
    if len(key_hits) == 1:
        return MatchResult(raw, key_hits[0], 0.98, "medicine_key", ((key_hits[0], 0.98),))
    if len(key_hits) > 1:
        # 용량으로 하나로 좁혀질 때만 키 매칭
        narrowed = [
            name
            for name in key_hits
            if strengths_compatible(raw, name, dosage_hint=dosage_hint)
            and (extract_strengths(raw) or dosage_hint)
        ]
        if len(narrowed) == 1:
            return MatchResult(
                raw,
                narrowed[0],
                0.98,
                "medicine_key_strength",
                ((narrowed[0], 0.98),),
            )
        # 용량 힌트 없이 여러 규격이면 키만으로 확정하지 않음

    ranked = _rank_candidates(raw, usable, dosage_hint=dosage_hint)
    candidates = tuple(
        (name, score) for name, score in ranked if score >= CANDIDATE_MIN
    )[:5]
    threshold = SIMILAR_ACCEPT if similar else AUTO_ACCEPT
    method = "similar" if similar else "fuzzy"
    if candidates and candidates[0][1] >= threshold:
        # 유사 추론은 2등과 격차가 너무 작으면 보류
        if similar and len(candidates) > 1 and (candidates[0][1] - candidates[1][1]) < 0.03:
            return MatchResult(raw, None, candidates[0][1], "none", candidates)
        name, score = candidates[0]
        return MatchResult(raw, name, score, method, candidates)
    return MatchResult(
        raw,
        None,
        candidates[0][1] if candidates else 0.0,
        "none",
        candidates,
    )
