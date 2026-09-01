"""Derive a short senior-friendly medicine category for UI parentheses."""

from __future__ import annotations

from typing import Any

from app.services.pharmacist.easy_category_db import lookup_easy_label


def derive_easy_category(
    *,
    product_name: str | None = None,
    ingredient: str | None = None,
    efficacy: str | None = None,
    usage: str | None = None,
    source_text: str | None = None,
) -> str | None:
    """Look up easy_category_map.db using official name/efficacy text."""
    name_blob = " ".join(str(part or "") for part in (product_name, ingredient))
    efficacy_blob = " ".join(
        str(part or "") for part in (efficacy, usage, source_text)
    )
    if not name_blob.strip() and not efficacy_blob.strip():
        return None
    return lookup_easy_label(name_text=name_blob, efficacy_text=efficacy_blob)


def derive_easy_category_from_medicine(med: dict[str, Any]) -> str | None:
    return derive_easy_category(
        product_name=med.get("product_name") or med.get("medicine_name"),
        ingredient=med.get("ingredient"),
        efficacy=med.get("efficacy") or med.get("efficacy_text"),
        usage=med.get("usage") or med.get("usage_text"),
        source_text=med.get("source_text")
        or med.get("cautions")
        or med.get("caution_text"),
    )


def format_display_name(name: str, easy_category: str | None) -> str:
    base = (name or "").strip()
    category = (easy_category or "").strip()
    if not base:
        return category
    if not category:
        return base
    return f"{base} ({category})"
