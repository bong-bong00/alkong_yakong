"""HTTP client for MFDS DrugPrdtPrmsnInfoService07."""

from __future__ import annotations

from typing import Any

import requests

from app.core.config import (
    MFDS_DRUG_PERMISSION_API_KEY,
    MFDS_DRUG_PERMISSION_BASE_URL,
    MFDS_DRUG_PERMISSION_DETAIL_PATH,
    MFDS_DRUG_PERMISSION_LIST_PATH,
)

BASE_URL = MFDS_DRUG_PERMISSION_BASE_URL
LIST_PATH = f"{BASE_URL}{MFDS_DRUG_PERMISSION_LIST_PATH}"
DETAIL_PATH = f"{BASE_URL}{MFDS_DRUG_PERMISSION_DETAIL_PATH}"
TIMEOUT = 30


def fetch_permission_list_page(
    *,
    page_no: int,
    num_of_rows: int = 500,
    item_name: str | None = None,
) -> dict[str, Any]:
    if not MFDS_DRUG_PERMISSION_API_KEY:
        raise RuntimeError("MFDS_DRUG_PERMISSION_API_KEY가 없습니다.")
    params: dict[str, Any] = {
        "serviceKey": MFDS_DRUG_PERMISSION_API_KEY,
        "pageNo": page_no,
        "numOfRows": num_of_rows,
        "type": "json",
    }
    if item_name:
        params["item_name"] = item_name
    response = requests.get(LIST_PATH, params=params, timeout=TIMEOUT)
    response.raise_for_status()
    return response.json()


def fetch_permission_detail(item_name: str) -> dict[str, Any] | None:
    if not MFDS_DRUG_PERMISSION_API_KEY:
        raise RuntimeError("MFDS_DRUG_PERMISSION_API_KEY가 없습니다.")
    response = requests.get(
        DETAIL_PATH,
        params={
            "serviceKey": MFDS_DRUG_PERMISSION_API_KEY,
            "pageNo": 1,
            "numOfRows": 1,
            "type": "json",
            "item_name": item_name,
        },
        timeout=TIMEOUT,
    )
    response.raise_for_status()
    items = extract_items(response.json())
    return items[0] if items else None


def extract_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    body = payload.get("body")
    if body is None and isinstance(payload.get("response"), dict):
        body = payload["response"].get("body")
    if not isinstance(body, dict):
        return []
    items = body.get("items")
    if isinstance(items, dict) and "item" in items:
        items = items["item"]
    if isinstance(items, dict):
        items = [items]
    return items if isinstance(items, list) else []


def extract_total_count(payload: dict[str, Any]) -> int:
    body = payload.get("body")
    if body is None and isinstance(payload.get("response"), dict):
        body = payload["response"].get("body")
    if not isinstance(body, dict):
        return 0
    try:
        return int(body.get("totalCount") or 0)
    except (TypeError, ValueError):
        return 0
