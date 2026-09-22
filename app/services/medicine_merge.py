"""Lossless merge policy for official medicine master data.

All OCR, pharmacist, and background-refresh paths must use this module instead
of replacing a richer ``medicines`` row with a partial API response.
"""

from __future__ import annotations

import re
from typing import Any


_HANGUL = re.compile(r"[가-힣]")
_SPACE = re.compile(r"\s+")
_STRENGTH = re.compile(
    r"\b\d+(?:\.\d+)?\s*(?:mg|mcg|μg|g|ml|mL|밀리그램|밀리그람|마이크로그램|밀리리터|%)\b",
    re.I,
)


def _text(value: Any) -> str:
    return _SPACE.sub(" ", str(value or "")).strip()


def _has_hangul(value: Any) -> bool:
    return bool(_HANGUL.search(str(value or "")))


def _ingredient_key(value: Any) -> str:
    return _SPACE.sub(" ", _STRENGTH.sub(" ", str(value or ""))).strip(
        " ,;|/·"
    ).casefold()


def _remember_ingredient_aliases(
    cursor,
    *,
    existing_ingredient: Any,
    incoming_ingredient: Any,
    canonical_ingredient: Any,
) -> None:
    canonical_key = _ingredient_key(canonical_ingredient)
    if not canonical_key:
        return
    try:
        for value in (existing_ingredient, incoming_ingredient, canonical_ingredient):
            alias_key = _ingredient_key(value)
            if not alias_key:
                continue
            cursor.execute(
                """
                INSERT INTO ingredient_aliases (
                    alias_key, canonical_key, display_name, source
                ) VALUES (?, ?, ?, 'official-merge')
                ON CONFLICT(alias_key) DO UPDATE SET
                    canonical_key=excluded.canonical_key,
                    display_name=excluded.display_name,
                    updated_at=CURRENT_TIMESTAMP
                """,
                (alias_key, canonical_key, _text(canonical_ingredient)),
            )
    except Exception:
        # Older databases are still usable until initialize_database creates it.
        return


def _use_incoming(existing: Any, incoming: Any, *, long_text: bool) -> str:
    """Choose the incoming value only when it cannot lower display quality."""
    old = _text(existing)
    new = _text(incoming)
    if not new:
        return old
    if not old:
        return new
    if _has_hangul(old) and not _has_hangul(new):
        return old
    if _has_hangul(new) and not _has_hangul(old):
        return new
    if long_text and len(new) < max(12, int(len(old) * 0.55)):
        return old
    return new


def merge_official_medicine(
    existing: dict[str, Any] | None,
    incoming: dict[str, Any],
) -> dict[str, Any]:
    """Return a field-wise merge that preserves richer existing information."""
    current = existing or {}
    product_name = _use_incoming(
        current.get("product_name"),
        incoming.get("product_name") or incoming.get("medicine_name"),
        long_text=False,
    )
    ingredient = _text(incoming.get("ingredient"))
    if ingredient == product_name:
        ingredient = ""
    return {
        "product_name": product_name,
        "ingredient": _use_incoming(
            current.get("ingredient"), ingredient, long_text=False
        ),
        "manufacturer": _use_incoming(
            current.get("manufacturer"), incoming.get("manufacturer"), long_text=False
        ),
        "efficacy": _use_incoming(
            current.get("efficacy"),
            incoming.get("efficacy") or incoming.get("efficacy_text"),
            long_text=True,
        ),
        "usage": _use_incoming(
            current.get("usage"), incoming.get("usage"), long_text=True
        ),
        "precautions": _use_incoming(
            current.get("precautions"),
            incoming.get("precautions") or incoming.get("cautions"),
            long_text=True,
        ),
        "image_url": _use_incoming(
            current.get("image_url"), incoming.get("image_url"), long_text=False
        ),
        "easy_category": _text(current.get("easy_category"))
        or _text(incoming.get("easy_category")),
    }


def upsert_official_medicine(
    cursor,
    *,
    medicine_code: str,
    incoming: dict[str, Any],
    easy_category: str | None = None,
) -> dict[str, Any]:
    """Insert/update one official medicine without destructive replacement."""
    row = cursor.execute(
        "SELECT * FROM medicines WHERE medicine_code=?", (medicine_code,)
    ).fetchone()
    existing = dict(row) if row else None
    merged = merge_official_medicine(
        existing,
        {**incoming, "easy_category": easy_category or incoming.get("easy_category")},
    )
    _remember_ingredient_aliases(
        cursor,
        existing_ingredient=(existing or {}).get("ingredient"),
        incoming_ingredient=incoming.get("ingredient"),
        canonical_ingredient=merged.get("ingredient"),
    )
    cursor.execute(
        """
        INSERT INTO medicines (
            medicine_code, product_name, ingredient, manufacturer,
            efficacy, usage, precautions, image_url, easy_category
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(medicine_code) DO UPDATE SET
            product_name=excluded.product_name,
            ingredient=excluded.ingredient,
            manufacturer=excluded.manufacturer,
            efficacy=excluded.efficacy,
            usage=excluded.usage,
            precautions=excluded.precautions,
            image_url=excluded.image_url,
            easy_category=excluded.easy_category,
            updated_at=CURRENT_TIMESTAMP
        """,
        (
            medicine_code,
            merged["product_name"] or medicine_code,
            merged["ingredient"] or None,
            merged["manufacturer"] or None,
            merged["efficacy"] or None,
            merged["usage"] or None,
            merged["precautions"] or None,
            merged["image_url"] or None,
            merged["easy_category"] or None,
        ),
    )
    saved = cursor.execute(
        "SELECT * FROM medicines WHERE medicine_code=?", (medicine_code,)
    ).fetchone()
    return dict(saved) if saved else {"medicine_code": medicine_code, **merged}
