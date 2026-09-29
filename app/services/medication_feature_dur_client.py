"""Read current medicines and DUR results from the medication-data service.

This module is used only by the team AI-pharmacist backend.  It deliberately
does not fall back to this process's SQLite database: the medication service is
the source of truth for OCR/manual registrations.
"""

from __future__ import annotations

from typing import Any
from urllib.parse import quote

import requests

from app.core.config import (
    MEDICATION_FEATURE_BASE_URL,
    MEDICATION_FEATURE_TIMEOUT_SECONDS,
)


_COMBINATION_TYPES = {"병용금기", "중복성분", "효능군중복"}


def load_remote_current_medicines(*, user_id: str) -> dict[str, Any]:
    """Load the signed-in user's active medicines from the source-of-truth service."""

    uid = str(user_id or "").strip()
    if not uid:
        return _unavailable("missing_user_id")
    if not MEDICATION_FEATURE_BASE_URL:
        return _unavailable("medication_service_not_configured")
    try:
        response = requests.get(
            f"{MEDICATION_FEATURE_BASE_URL}/api/v1/users/{quote(uid, safe='')}/medicines",
            timeout=MEDICATION_FEATURE_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
    except (requests.RequestException, ValueError):
        return _unavailable("medication_service_unavailable")

    if not isinstance(payload, dict) or not isinstance(payload.get("medicines"), list):
        return _malformed()

    active_rows = [
        row
        for row in payload["medicines"]
        if isinstance(row, dict)
        and str(row.get("status") or "active") == "active"
    ]
    if not active_rows:
        return {"status": "empty", "items": [], "reason": "no_active_medicines"}

    items: list[dict[str, str]] = []
    names_by_code: dict[str, str] = {}
    incomplete = False
    for row in active_rows:
        code = str(row.get("medicine_code") or row.get("item_seq") or "").strip()
        name = str(
            row.get("official_product_name")
            or row.get("product_name")
            or ""
        ).strip()
        if not code or not name:
            incomplete = True
            continue
        previous_name = names_by_code.get(code)
        if previous_name is not None:
            if previous_name != name:
                incomplete = True
            continue
        names_by_code[code] = name
        items.append({"medicine_code": code, "product_name": name})

    if incomplete or len(items) != len({
        str(row.get("medicine_code") or row.get("item_seq") or "").strip()
        for row in active_rows
        if str(row.get("medicine_code") or row.get("item_seq") or "").strip()
    }):
        return {
            "status": "incomplete",
            "items": items,
            "reason": "medicine_identity_incomplete",
        }
    return {"status": "current", "items": items, "reason": None}


def load_remote_combination_context(
    *,
    user_id: str,
    selected_medicine: dict[str, Any] | None,
) -> dict[str, Any]:
    """Return prompt-ready DUR context without consulting the team DB."""

    uid = str(user_id or "").strip()
    if not uid:
        return _unavailable("missing_user_id")
    if not MEDICATION_FEATURE_BASE_URL:
        return _unavailable("medication_service_not_configured")
    medicines_context = load_remote_current_medicines(user_id=uid)
    if medicines_context["status"] != "current":
        return {
            **medicines_context,
            "has_risk": None,
        }
    medicines = medicines_context["items"]

    if selected_medicine is not None and not isinstance(selected_medicine, dict):
        return _unavailable("selected_medicine_unavailable")

    selected_code = str((selected_medicine or {}).get("medicine_code") or "").strip()
    selected_name = str((selected_medicine or {}).get("product_name") or "").strip()
    if selected_medicine is not None and (not selected_code or not selected_name):
        return _unavailable("selected_medicine_unavailable")

    selected_row = next(
        (
            row
            for row in medicines
            if str(row.get("medicine_code") or "").strip() == selected_code
        ),
        None,
    ) if selected_medicine is not None else None
    if selected_medicine is not None and selected_row is None:
        return _unavailable("selected_medicine_not_registered")
    stored_name = str(
        (selected_row or {}).get("product_name")
        or ""
    ).strip()
    if selected_medicine is not None and (
        not stored_name or stored_name != selected_name
    ):
        return _unavailable("selected_medicine_identity_mismatch")

    try:
        dur_response = requests.post(
            f"{MEDICATION_FEATURE_BASE_URL}/api/v1/dur/analyze",
            json={"user_id": uid, "medicine_codes": []},
            timeout=MEDICATION_FEATURE_TIMEOUT_SECONDS,
        )
        dur_response.raise_for_status()
        payload = dur_response.json()
    except (requests.RequestException, ValueError):
        return _unavailable("dur_service_unavailable")

    if not isinstance(payload, dict):
        return _malformed()
    assessment = payload.get("assessment_status")
    analysis_complete = payload.get("analysis_complete")
    incomplete = payload.get("incomplete")
    has_risk = payload.get("has_risk")
    matches = payload.get("matches")
    if (
        assessment not in {"SAFE", "RISK_FOUND", "INCOMPLETE"}
        or not isinstance(analysis_complete, bool)
        or not isinstance(incomplete, bool)
        or not isinstance(has_risk, bool)
        or not isinstance(matches, list)
        or any(not isinstance(item, dict) for item in matches)
    ):
        return _malformed()

    if assessment == "INCOMPLETE" or not analysis_complete or incomplete:
        return {
            "status": "incomplete",
            "items": [],
            "has_risk": None,
            "reason": "dur_analysis_incomplete",
        }

    items = [
        dict(item)
        for item in matches
        if item.get("type") in _COMBINATION_TYPES
    ]
    matched_types = {
        str(item.get("type") or "").strip()
        for item in items
        if str(item.get("type") or "").strip()
    }
    combination_has_risk = bool(items)
    if assessment == "SAFE" and (has_risk or matches):
        return _malformed()
    if assessment == "RISK_FOUND" and not has_risk:
        return _malformed()
    return {
        "status": "current",
        "items": items,
        "has_risk": combination_has_risk,
        "reason": None,
        "checked_types": sorted(_COMBINATION_TYPES),
        "zero_result_types": sorted(_COMBINATION_TYPES - matched_types),
    }


def _unavailable(reason: str) -> dict[str, Any]:
    return {
        "status": "missing",
        "items": [],
        "has_risk": None,
        "reason": reason,
    }


def _malformed() -> dict[str, Any]:
    return {
        "status": "malformed",
        "items": [],
        "has_risk": None,
        "reason": "invalid_medication_service_response",
    }
