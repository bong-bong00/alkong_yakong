"""Chat flow: candidate extraction -> matching -> retrieval -> generation -> guard."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from app.services.matching.name_matcher import match_medicine_name
from app.services.pharmacist.generate import generate_from_source
from app.services.pharmacist.guard import guard_reply
from app.services.pharmacist.retrieve import retrieve_official
from app.services.pharmacist.spell import extract_drug_name_candidates


@dataclass(frozen=True)
class ChatPipelineResult:
    ok: bool
    reply: str
    trace: dict[str, Any] = field(default_factory=dict)


def run_chat_pipeline(message: str, lexicon: list[str] | None = None) -> ChatPipelineResult:
    original = (message or "").strip()
    candidates = extract_drug_name_candidates(original, lexicon)
    if not candidates:
        return _failure(original, "약 이름을 먼저 선택하거나 입력해주세요.", "spell")

    corrected = candidates[0]
    name_match_score: float | None = None
    name_match_method = "official_search"
    if lexicon:
        match = match_medicine_name(candidates[0], lexicon)
        if not match.matched_name and match.candidates:
            return ChatPipelineResult(
                False,
                "약 이름을 정확히 확인하지 못했어요.",
                {
                    "original": original,
                    "corrected": None,
                    "candidates": list(match.candidates),
                    "name_match_score": round(match.score * 100, 1),
                    "name_match_method": "candidate",
                    "source": None,
                    "rejected": [],
                    "evidence_score": 0.0,
                    "stage": "match",
                },
            )
        if match.matched_name:
            corrected = match.matched_name
            name_match_score = round(match.score * 100, 1)
            name_match_method = match.method

    official = retrieve_official(corrected)
    if not official:
        return ChatPipelineResult(
            False,
            "공식 자료에서 그 약을 찾지 못했어요.",
            {
                "original": original,
                "corrected": corrected,
                "name_match_score": name_match_score,
                "name_match_method": name_match_method,
                "source": None,
                "rejected": [],
                "evidence_score": 0.0,
                "stage": "retrieve",
            },
        )

    official_name = official.get("medicine", {}).get("product_name")
    corrected = official_name or corrected
    try:
        draft = generate_from_source(original, official)
    except Exception:
        return ChatPipelineResult(
            False,
            "공식 자료를 바탕으로 답변을 만들지 못했어요.",
            {
                "original": original,
                "corrected": corrected,
                "name_match_score": name_match_score,
                "name_match_method": name_match_method,
                "source": official.get("source"),
                "rejected": [],
                "evidence_score": 0.0,
                "stage": "generate",
            },
        )

    guarded = guard_reply(draft, official.get("source_text", ""))
    trace = {
        "original": original,
        "corrected": corrected,
        "name_match_score": name_match_score,
        "name_match_method": name_match_method,
        "source": official.get("source"),
        "rejected": list(guarded.rejected),
        "evidence_score": guarded.evidence_score,
    }
    if not guarded.allowed:
        return ChatPipelineResult(
            False,
            "공식 자료에 근거한 답변을 확인하지 못했어요.",
            {**trace, "stage": "guard"},
        )
    return ChatPipelineResult(True, guarded.reply, {**trace, "stage": "done"})


def _failure(original: str, reply: str, stage: str) -> ChatPipelineResult:
    return ChatPipelineResult(
        False,
        reply,
        {
            "original": original,
            "corrected": None,
            "name_match_score": None,
            "name_match_method": None,
            "source": None,
            "rejected": [],
            "evidence_score": 0.0,
            "stage": stage,
        },
    )
