"""Match OCR medicine names against the verified local lexicon."""

from __future__ import annotations

from dataclasses import dataclass
from difflib import SequenceMatcher
import re


AUTO_ACCEPT = 0.90
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
    normalized = re.sub(r"\d+(?:\.\d+)?(?:mg|ml|g)", "", normalized)
    for dosage_form in ("필름코팅정", "서방정", "연질캡슐", "캡슐", "정", "시럽"):
        if normalized.endswith(dosage_form):
            normalized = normalized[: -len(dosage_form)]
            break
    return normalized


def match_medicine_name(query: str, lexicon: list[str]) -> MatchResult:
    raw = (query or "").strip()
    if not raw or not lexicon:
        return MatchResult(raw, None, 0.0, "none", ())

    for name in lexicon:
        if name == raw:
            return MatchResult(raw, name, 1.0, "exact", ((name, 1.0),))

    normalized = _normalize(raw)
    for name in lexicon:
        if _normalize(name) == normalized:
            return MatchResult(raw, name, 0.99, "normalized", ((name, 0.99),))

    medicine_key = _medicine_key(raw)
    for name in lexicon:
        if medicine_key and _medicine_key(name) == medicine_key:
            return MatchResult(raw, name, 0.98, "medicine_key", ((name, 0.98),))

    ranked = sorted(
        (
            (name, SequenceMatcher(None, medicine_key, _medicine_key(name)).ratio())
            for name in lexicon
        ),
        key=lambda item: item[1],
        reverse=True,
    )
    candidates = tuple(
        (name, score) for name, score in ranked if score >= CANDIDATE_MIN
    )[:5]
    if candidates and candidates[0][1] >= AUTO_ACCEPT:
        name, score = candidates[0]
        return MatchResult(raw, name, score, "fuzzy", candidates)
    return MatchResult(
        raw,
        None,
        candidates[0][1] if candidates else 0.0,
        "none",
        candidates,
    )
