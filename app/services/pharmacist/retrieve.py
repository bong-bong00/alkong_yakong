"""Retrieve verified local or MFDS medicine information."""

from __future__ import annotations

from typing import Any

from app.database import get_connection
from app.services.external_api_service import search_drug_info_by_name


def retrieve_official(drug_name: str) -> dict[str, Any] | None:
    name = (drug_name or "").strip()
    if not name:
        return None

    local = _find_local(name)
    if local:
        return {
            "source": "local",
            "medicine": local,
            "source_text": _local_text(local),
        }

    try:
        result = search_drug_info_by_name(name, num_of_rows=5)
    except Exception:
        return None
    items = result.get("items") if isinstance(result, dict) else None
    if not items:
        return None
    return {
        "source": "식약처 e약은요",
        "medicine": items[0],
        "source_text": _local_text(items[0]),
    }


def _find_local(name: str) -> dict[str, Any] | None:
    compact = "".join(name.casefold().split())
    conn = get_connection()
    try:
        rows = conn.execute(
            "SELECT * FROM medicines WHERE product_name IS NOT NULL"
        ).fetchall()
        for row in rows:
            product_name = str(row["product_name"] or "")
            if "".join(product_name.casefold().split()) == compact:
                return dict(row)
        return None
    finally:
        conn.close()


def _local_text(value: dict[str, Any]) -> str:
    fields = (
        "product_name", "ingredient", "efficacy", "usage", "precautions",
        "cautions", "interaction", "side_effects", "storage",
    )
    return "\n".join(
        f"{field}: {value[field]}"
        for field in fields
        if value.get(field)
    )
