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
    if not isinstance(selected_medicine, dict):
        return _unavailable("selected_medicine_unavailable")

    selected_code = str(selected_medicine.get("medicine_code") or "").strip()
    selected_name = str(selected_medicine.get("product_name") or "").strip()
    if not selected_code or not selected_name:
        return _unavailable("selected_medicine_unavailable")

    try:
        medicines_response = requests.get(
            f"{MEDICATION_FEATURE_BASE_URL}/api/v1/users/{quote(uid, safe='')}/medicines",
            timeout=MEDICATION_FEATURE_TIMEOUT_SECONDS,
        )
        medicines_response.raise_for_status()
        medicines_payload = medicines_response.json()
    except (requests.RequestException, ValueError):
        return _unavailable("medication_service_unavailable")

    if not isinstance(medicines_payload, dict):
        return _malformed()
    medicines = medicines_payload.get("medicines")
    if not isinstance(medicines, list):
        return _malformed()

    selected_row = next(
        (
            row
            for row in medicines
            if isinstance(row, dict)
            and str(row.get("status") or "active") == "active"
            and str(row.get("medicine_code") or "").strip() == selected_code
        ),
        None,
    )
    if selected_row is None:
        return _unavailable("selected_medicine_not_registered")
    stored_name = str(
        selected_row.get("product_name")
        or selected_row.get("official_product_name")
        or selected_row.get("display_name")
        or ""
    ).strip()
    if not stored_name or stored_name != selected_name:
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
