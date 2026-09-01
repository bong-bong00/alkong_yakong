"""Chat flow: candidate extraction -> matching -> retrieval -> fixed/DB reply."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from app.services.matching.name_matcher import match_medicine_name
from app.services.mfds_drug_permission.db import search_permission_names
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
    enriched_lexicon = _enrich_lexicon(original, lexicon)
    candidates = extract_drug_name_candidates(original, enriched_lexicon)
    if not candidates:
        return _failure(original, "약 이름을 먼저 선택하거나 입력해주세요.", "spell")

    corrected = candidates[0]
    name_match_score: float | None = None
    name_match_method = "official_search"
    if enriched_lexicon:
        match = match_medicine_name(candidates[0], enriched_lexicon)
        if not match.matched_name and match.candidates:
            return ChatPipelineResult(
                False,
                "약 이름을 정확히 확인하지 못했어요. 목록에서 약을 골라 주세요.",
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
    faq_kind = _faq_kind(original)
    reply = _fixed_db_reply(faq_kind, official, corrected)
    trace = {
        "original": original,
        "corrected": corrected,
        "name_match_score": name_match_score,
        "name_match_method": name_match_method,
        "source": official.get("source"),
        "rejected": [],
        "evidence_score": 100.0,
        "stage": "fixed",
        "faq_kind": faq_kind,
    }
    if reply:
        return ChatPipelineResult(True, reply, {**trace, "stage": "done"})

    # 고정 답이 애매할 때만 생성→가드. 실패하면 원문 발췌로 대체.
    try:
        draft = generate_from_source(original, official)
        guarded = guard_reply(draft, official.get("source_text", ""))
        if guarded.allowed and guarded.reply.strip():
            return ChatPipelineResult(
                True,
                guarded.reply,
                {
                    **trace,
                    "rejected": list(guarded.rejected),
                    "evidence_score": guarded.evidence_score,
                    "stage": "done",
                },
            )
    except Exception:
        pass

    fallback = _official_excerpt_reply(official, corrected)
    if fallback:
        return ChatPipelineResult(True, fallback, {**trace, "stage": "excerpt"})
    return ChatPipelineResult(
        False,
        "공식 자료로 안내할 내용이 부족해요. 의사·약사에게 확인해 주세요.",
        {**trace, "stage": "guard", "evidence_score": 0.0},
    )


def _enrich_lexicon(message: str, lexicon: list[str] | None) -> list[str]:
    """자동완성·허가DB 이름으로 사전을 보강해 오타(라이트장제수→라이트정제수)를 잡는다."""
    names: list[str] = []
    seen: set[str] = set()

    def _add(label: str) -> None:
        text = (label or "").strip()
        if text and text not in seen:
            seen.add(text)
            names.append(text)

    for label in lexicon or []:
        _add(label)

    tokens = extract_drug_name_candidates(message, None)
    for token in tokens:
        _add(token)
        try:
            for hit in search_permission_names(token[:2], limit=8):
                _add(hit)
            for hit in search_permission_names(token, limit=8):
                _add(hit)
        except Exception:
            continue
    return names


def _faq_kind(message: str) -> str | None:
    compact = "".join((message or "").casefold().split())
    if any(key in compact for key in ("안먹", "깜빡", "잊었", "어제안")):
        return "missed"
    if any(key in compact for key in ("같이먹", "겹쳐", "같이")):
        return "together"
    if any(key in compact for key in ("설명", "뭐야", "효능", "뭐에")):
        return "explain"
    if any(key in compact for key in ("언제먹", "복용", "어떻게먹", "밥전", "식후")):
        return "usage"
    return None


def _fixed_db_reply(kind: str | None, official: dict[str, Any], name: str) -> str | None:
    """DB/공식 필드만으로 정해진 답을 만든다. 추측 문장 금지."""
    med = official.get("medicine") or {}
    product = str(med.get("product_name") or name).strip()
    efficacy = _short_field(med.get("efficacy") or med.get("efficacy_text"))
    usage = _short_field(med.get("usage") or med.get("usage_text"))
    caution = _short_field(
        med.get("cautions") or med.get("caution_text") or med.get("precautions")
    )

    if kind == "missed":
        parts = [
            f"{product}{_object_particle(product)} 깜빡하고 안 드셨다면, 임의로 양을 늘려 드시지 마세요.",
            "다음 복용 때까지 기다릴지, 지금 드실지는 의사·약사에게 확인하는 게 안전해요.",
        ]
        if usage:
            parts.append(f"공식 복용 안내: {usage}")
        return "\n".join(parts)

    if kind == "together":
        parts = [
            f"{product}{_object_particle(product)} 다른 약과 같이 드실지는 혼자 판단하지 마세요.",
            "먹는 약을 모두 알려 드리고 의사·약사에게 확인하세요.",
        ]
        if caution:
            parts.append(f"공식 주의: {caution}")
        return "\n".join(parts)

    if kind == "usage":
        if usage:
            return f"{product} 공식 복용 안내입니다.\n{usage}\n궁금하면 의사·약사에게 물어보세요."
        return (
            f"{product}의 자세한 복용 방법은 공식 자료에 짧게 안내되어 있지 않아요. "
            "의사·약사에게 확인하세요."
        )

    if kind == "explain":
        parts = [f"{product} 공식 안내입니다."]
        if efficacy:
            parts.append(f"효능: {efficacy}")
        if usage:
            parts.append(f"복용: {usage}")
        if caution:
            parts.append(f"주의: {caution}")
        if len(parts) == 1:
            return (
                f"{product}에 대해 보여줄 공식 요약이 부족해요. "
                "의사·약사에게 확인해 주세요."
            )
        parts.append("자세한 건 의사·약사에게 확인하세요.")
        return "\n".join(parts)

    return None


def _official_excerpt_reply(official: dict[str, Any], name: str) -> str | None:
    med = official.get("medicine") or {}
    product = str(med.get("product_name") or name).strip()
    efficacy = _short_field(med.get("efficacy") or med.get("efficacy_text"))
    usage = _short_field(med.get("usage") or med.get("usage_text"))
    if not efficacy and not usage:
        return None
    parts = [f"{product} 공식 자료 요약입니다."]
    if efficacy:
        parts.append(f"효능: {efficacy}")
    if usage:
        parts.append(f"복용: {usage}")
    parts.append("임의로 판단하지 말고 의사·약사에게 확인하세요.")
    return "\n".join(parts)


def _object_particle(name: str) -> str:
    """한글 받침에 따라 을/를 선택."""
    if not name:
        return "를"
    code = ord(name[-1])
    if 0xAC00 <= code <= 0xD7A3:
        return "을" if (code - 0xAC00) % 28 else "를"
    return "를"


def _short_field(value: Any, limit: int = 120) -> str:
    text = " ".join(str(value or "").split())
    if not text:
        return ""
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


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
