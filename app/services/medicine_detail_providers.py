"""Pluggable sources for verified, complete ingredient explanations.

Only source-verified and reviewed ingredient copy may reach the detail screen.
An official provider can implement the same interface later without changing
the detail API or Flutter response shape.
"""

from __future__ import annotations

import re
from typing import Any, Protocol


_SPACE = re.compile(r"\s+")
_INCOMPLETE_ENDING = re.compile(r"(?:따라|따르면|및|또는|그리고|,|:|：|\(|·)\s*$")
_COMPLETE_ENDING = re.compile(
    r"(?:이에요|예요|해요|돼요|줘요|있어요|없어요|됩니다|합니다|입니다|"
    r"있습니다|없습니다|돕습니다|조절합니다|사용됩니다|성분이다|성분입니다)"
    r"[.!?]?\s*$"
)
_HIDDEN_COPY = ("준비 중", "준비중", "확인 중", "확인중")
_MAX_SENTENCE_CHARS = 180
_SOURCE_PREAMBLE = re.compile(
    r"(?:공식\s*허가정보|식약처\s*정보|공식\s*자료)"
    r"(?:에\s*따라|에\s*따르면|를\s*바탕으로)\s*"
)


def clean_ingredient_explanation(value: Any) -> str:
    """Normalize copy and leave source attribution to the source card."""
    text = _SOURCE_PREAMBLE.sub("", str(value or ""))
    return _SPACE.sub(" ", text).strip()


def is_displayable_ingredient_explanation(value: Any) -> bool:
    """Reject drafts, dangling official-purpose fragments, and cut sentences."""
    text = clean_ingredient_explanation(value)
    if not text or any(marker in text for marker in _HIDDEN_COPY):
        return False
    if _INCOMPLETE_ENDING.search(text):
        return False
    if not _COMPLETE_ENDING.search(text):
        return False
    sentences = [item for item in re.split(r"(?<=[.!?])\s+", text) if item.strip()]
    return len(sentences) <= 2 and all(
        len(sentence) <= _MAX_SENTENCE_CHARS for sentence in sentences
    )


class IngredientExplanationProvider(Protocol):
    name: str

    def find_reviewed(
        self,
        cursor,
        ingredients: list[dict[str, str]],
    ) -> dict[str, dict[str, Any]]:
        """Return reviewed explanations keyed by normalized ingredient key."""


class LocalReviewedIngredientProvider:
    name = "local-reviewed"

    def find_reviewed(
        self,
        cursor,
        ingredients: list[dict[str, str]],
    ) -> dict[str, dict[str, Any]]:
        result: dict[str, dict[str, Any]] = {}
        for ingredient in ingredients:
            canonical_key = ingredient["key"]
            try:
                alias = cursor.execute(
                    "SELECT canonical_key FROM ingredient_aliases WHERE alias_key=?",
                    (ingredient["key"],),
                ).fetchone()
                if alias and alias["canonical_key"]:
                    canonical_key = str(alias["canonical_key"])
            except Exception:
                pass
            row = cursor.execute(
                """
                SELECT explanation, role_explanation, use_help,
                       role_group, group_explanation,
                       source, source_verified, content_version
                FROM ingredient_explanations
                WHERE normalized_key=? AND review_status='REVIEWED'
                  AND source_verified=1
                """,
                (canonical_key,),
            ).fetchone()
            if row and is_displayable_ingredient_explanation(row["explanation"]):
                result[ingredient["key"]] = dict(row)
        return result


INGREDIENT_EXPLANATION_PROVIDERS: tuple[IngredientExplanationProvider, ...] = (
    LocalReviewedIngredientProvider(),
)


def find_reviewed_ingredient_explanations(
    cursor,
    ingredients: list[dict[str, str]],
) -> dict[str, dict[str, Any]]:
    combined: dict[str, dict[str, Any]] = {}
    for provider in INGREDIENT_EXPLANATION_PROVIDERS:
        for key, value in provider.find_reviewed(cursor, ingredients).items():
            combined.setdefault(key, {**value, "provider": provider.name})
    return combined
