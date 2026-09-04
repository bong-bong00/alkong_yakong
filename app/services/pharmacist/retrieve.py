"""Retrieve verified MFDS drug permission medicine information."""

from __future__ import annotations

from typing import Any

from app.services.mfds_drug_permission.db import (
    find_permission_product,
    product_to_medicine,
)
from app.services.mfds_drug_permission.sync import lookup_permission_by_ocr_name


def retrieve_official(
    drug_name: str,
    *,
    dosage_hint: str | float | None = None,
) -> dict[str, Any] | None:
    name = (drug_name or "").strip()
    if not name:
        return None
    try:
        from app.services.ocr.parser import product_search_name

        name = product_search_name(name)
        hangul = "".join(ch for ch in name if "가" <= ch <= "힣")
        if hangul and len(hangul) < 2:
            return None
    except Exception:
        pass

    # OCR 공식 찾기: 로컬 허가 DB만. 실시간 API는 시간 초과로 처방전 전체를 실패시킨다.
    return _find_permission_local(name, dosage_hint=dosage_hint)


def _find_permission_local(
    name: str,
    *,
    dosage_hint: str | float | None = None,
) -> dict[str, Any] | None:
    try:
        row = find_permission_product(name)
    except Exception:
        return None
    if not row:
        return None
    return _permission_result(row)


def _find_permission_live(
    name: str,
    *,
    dosage_hint: str | float | None = None,
) -> dict[str, Any] | None:
    try:
        row = lookup_permission_by_ocr_name(
            name,
            dosage_hint=dosage_hint,
            allow_similar=False,
        )
    except Exception:
        return None
    return _permission_result(row)


def _permission_result(row: dict[str, Any] | None) -> dict[str, Any] | None:
    if not row:
        return None
    medicine = product_to_medicine(row)
    source_text = _local_text(medicine)
    if not source_text.strip() and medicine.get("product_name"):
        source_text = f"product_name: {medicine['product_name']}"
    if not source_text.strip():
        return None
    return {
        "source": "식약처 의약품 제품 허가정보",
        "medicine": medicine,
        "source_text": source_text,
    }


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
