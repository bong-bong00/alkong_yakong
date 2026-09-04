"""Retrieve verified local or MFDS medicine information."""

from __future__ import annotations

from typing import Any

from app.database import get_connection
from app.services.external_api_service import search_drug_info_by_name
from app.services.matching.name_matcher import match_medicine_name
from app.services.mfds_drug_permission.db import (
    find_permission_product,
    product_to_medicine,
    search_permission_names,
)
from app.services.mfds_drug_permission.sync import (
    ensure_detail_for_product,
    lookup_permission_by_ocr_name,
)


def retrieve_official(
    drug_name: str,
    *,
    dosage_hint: str | float | None = None,
) -> dict[str, Any] | None:
    name = (drug_name or "").strip()
    if not name:
        return None
    truncated = False
    try:
        from app.services.ocr.parser import (
            _clean_drug_label,
            looks_truncated_ocr_name,
        )

        truncated = looks_truncated_ocr_name(name)
        cleaned = _clean_drug_label(name)
        if cleaned:
            name = cleaned
        hangul = "".join(ch for ch in name if "가" <= ch <= "힣")
        # 가려져서 한글이 거의 안 남으면 추측하지 않음
        if hangul and len(hangul) < 2:
            return None
    except Exception:
        pass

    # 1순위: 허가정보 미러 DB
    permission = _find_permission(name, dosage_hint=dosage_hint, similar=False)
    if permission:
        return permission

    fuzzy = _find_permission_fuzzy(name, dosage_hint=dosage_hint, similar=False)
    if fuzzy:
        return fuzzy

    # 실시간 정확 매칭 → 실패 시 유사 추론
    live = _find_permission_live(name, dosage_hint=dosage_hint, allow_similar=True)
    if live:
        return live

    # DB/퍼지 유사 추론 (미매칭 보완)
    permission = _find_permission(name, dosage_hint=dosage_hint, similar=True)
    if permission:
        return permission
    fuzzy = _find_permission_fuzzy(name, dosage_hint=dosage_hint, similar=True)
    if fuzzy:
        return fuzzy

    local = _find_local(name)
    if local:
        return {
            "source": "local",
            "medicine": local,
            "source_text": _local_text(local),
        }

    try:
        result = search_drug_info_by_name(name, num_of_rows=8)
    except Exception:
        result = None
    items = result.get("items") if isinstance(result, dict) else None
    if items:
        labels = [
            str(item.get("product_name") or item.get("medicine_name") or "")
            for item in items
        ]
        for similar in (False, True):
            match = match_medicine_name(
                name,
                [label for label in labels if label],
                dosage_hint=dosage_hint,
                similar=similar,
            )
            if not match.matched_name:
                continue
            for candidate in items:
                label = str(
                    candidate.get("product_name") or candidate.get("medicine_name") or ""
                )
                if label == match.matched_name:
                    return {
                        "source": "식약처 e약은요",
                        "medicine": candidate,
                        "source_text": _local_text(candidate),
                    }
    return None


def _find_permission_live(
    name: str,
    *,
    dosage_hint: str | float | None = None,
    allow_similar: bool = True,
) -> dict[str, Any] | None:
    try:
        row = lookup_permission_by_ocr_name(
            name,
            dosage_hint=dosage_hint,
            allow_similar=allow_similar,
        )
    except Exception:
        return None
    return _permission_result(row)


def _find_permission(
    name: str,
    *,
    dosage_hint: str | float | None = None,
    similar: bool = False,
) -> dict[str, Any] | None:
    try:
        row = find_permission_product(name)
    except Exception:
        return None
    if not row:
        return None
    official = str(row.get("item_name") or "")
    match = match_medicine_name(
        name,
        [official],
        dosage_hint=dosage_hint,
        similar=similar,
    )
    if not match.matched_name:
        return None
    return _permission_result(row)


def _find_permission_fuzzy(
    name: str,
    *,
    dosage_hint: str | float | None = None,
    similar: bool = False,
) -> dict[str, Any] | None:
    try:
        candidates = search_permission_names(name[:2], limit=20)
        if len(name) >= 3:
            candidates = list(
                dict.fromkeys(candidates + search_permission_names(name[:3], limit=20))
            )
        if len(name) >= 4:
            candidates = list(
                dict.fromkeys(candidates + search_permission_names(name[:4], limit=20))
            )
    except Exception:
        return None
    if not candidates:
        return None
    match = match_medicine_name(
        name,
        candidates,
        dosage_hint=dosage_hint,
        similar=similar,
    )
    chosen = match.matched_name
    if not chosen:
        return None
    try:
        row = find_permission_product(chosen)
    except Exception:
        return None
    return _permission_result(row)


def _permission_result(row: dict[str, Any] | None) -> dict[str, Any] | None:
    if not row:
        return None
    if not row.get("detail_synced"):
        ensure_detail_for_product(str(row["item_seq"]), str(row["item_name"]))
        row = find_permission_product(str(row["item_name"])) or row
    medicine = product_to_medicine(row)
    # 상세가 비어도 제품명만이라도 있으면 고정 안내에는 쓸 수 있다.
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


def _find_local(name: str) -> dict[str, Any] | None:
    compact = "".join(name.casefold().split())
    conn = get_connection()
    try:
        rows = conn.execute(
            """
            SELECT * FROM medicines
            WHERE product_name IS NOT NULL
              AND medicine_code NOT LIKE 'OCR-%'
            """
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
