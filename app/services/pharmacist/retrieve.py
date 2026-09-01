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
from app.services.mfds_drug_permission.sync import ensure_detail_for_product


def retrieve_official(drug_name: str) -> dict[str, Any] | None:
    name = (drug_name or "").strip()
    if not name:
        return None

    # 1순위: 허가정보 미러 DB (API 복사본)
    permission = _find_permission(name)
    if permission:
        return permission

    # 1순위 보완: 오타·비슷한 이름 (라이트장제수 → 라이트정제수)
    fuzzy = _find_permission_fuzzy(name)
    if fuzzy:
        return fuzzy

    # 2순위: 로컬 medicines
    local = _find_local(name)
    if local:
        return {
            "source": "local",
            "medicine": local,
            "source_text": _local_text(local),
        }

    # 3순위: e약은요 실시간 API
    try:
        result = search_drug_info_by_name(name, num_of_rows=5)
    except Exception:
        result = None
    items = result.get("items") if isinstance(result, dict) else None
    if items:
        return {
            "source": "식약처 e약은요",
            "medicine": items[0],
            "source_text": _local_text(items[0]),
        }
    return None


def _find_permission(name: str) -> dict[str, Any] | None:
    try:
        row = find_permission_product(name)
    except Exception:
        return None
    return _permission_result(row)


def _find_permission_fuzzy(name: str) -> dict[str, Any] | None:
    try:
        candidates = search_permission_names(name[:2], limit=20)
        if len(name) >= 3:
            candidates = list(
                dict.fromkeys(candidates + search_permission_names(name[:3], limit=20))
            )
    except Exception:
        return None
    if not candidates:
        return None
    match = match_medicine_name(name, candidates)
    # 채팅 자동확정(0.90)보다 조금 낮게: DB에 있는 가장 가까운 공식명으로 연결
    chosen = match.matched_name
    if not chosen and match.candidates and match.candidates[0][1] >= 0.80:
        chosen = match.candidates[0][0]
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
