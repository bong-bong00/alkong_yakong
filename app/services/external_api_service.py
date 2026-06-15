import logging
import re
from html import unescape
from typing import Any

import requests
from fastapi import HTTPException

from app.core.config import E_DRUG_API_KEY, E_DRUG_BASE_URL


logger = logging.getLogger(__name__)
TIMEOUT_SECONDS = 10


def fetch_e_drug_info(
    *,
    medicine_code: str | None = None,
    medicine_name: str | None = None,
) -> dict[str, Any] | None:
    if not E_DRUG_API_KEY:
        logger.info("E_DRUG_API_KEY is not configured; using local drug fallback.")
        return None

    params: dict[str, Any] = {
        "ServiceKey": E_DRUG_API_KEY,
        "pageNo": 1,
        "numOfRows": 10,
        "type": "json",
    }
    if medicine_code and medicine_code.isdigit():
        params["itemSeq"] = medicine_code
    elif medicine_name:
        params["itemName"] = medicine_name
    elif medicine_code:
        params["itemName"] = medicine_code
    else:
        return None

    try:
        response = requests.get(
            E_DRUG_BASE_URL,
            params=params,
            timeout=TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
        items = _extract_items(payload)
        if not items:
            logger.info(
                "e약은요 returned no result for code=%s name=%s",
                medicine_code,
                medicine_name,
            )
            return None
        return _normalize_item(items[0])
    except (requests.RequestException, ValueError, TypeError, KeyError) as error:
        logger.warning(
            "e약은요 lookup failed (%s).",
            type(error).__name__,
        )
        return None


def search_drug_info_by_name(
    name: str,
    page_no: int = 1,
    num_of_rows: int = 10,
) -> dict:
    if not E_DRUG_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="E_DRUG_API_KEY가 설정되지 않았습니다.",
        )

    params = {
        "ServiceKey": E_DRUG_API_KEY,
        "pageNo": page_no,
        "numOfRows": num_of_rows,
        "itemName": name,
        "type": "json",
    }
    try:
        response = requests.get(
            E_DRUG_BASE_URL,
            params=params,
            timeout=TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        items = _extract_items(response.json())
    except requests.Timeout as error:
        raise HTTPException(status_code=504, detail="식약처 API 타임아웃") from error
    except requests.RequestException as error:
        raise HTTPException(
            status_code=502,
            detail="식약처 API 호출에 실패했습니다.",
        ) from error
    except (ValueError, TypeError, KeyError) as error:
        raise HTTPException(
            status_code=502,
            detail="식약처 API 응답 형식이 올바르지 않습니다.",
        ) from error

    normalized = [_normalize_item(item) for item in items]
    return {"query": name, "count": len(normalized), "items": normalized}


def _extract_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    body = payload.get("body")
    if body is None:
        body = payload.get("response", {}).get("body", {})
    items = body.get("items", []) if isinstance(body, dict) else []
    if isinstance(items, dict):
        nested = items.get("item")
        if nested is not None:
            items = nested
        else:
            items = [items]
    if isinstance(items, dict):
        items = [items]
    return items if isinstance(items, list) else []


def _normalize_item(item: dict[str, Any]) -> dict[str, Any]:
    cautions = "\n".join(
        value
        for value in (
            _clean_text(item.get("atpnWarnQesitm")),
            _clean_text(item.get("atpnQesitm")),
        )
        if value
    )
    return {
        "medicine_code": _clean_text(item.get("itemSeq")),
        "medicine_name": _clean_text(item.get("itemName")),
        "product_name": _clean_text(item.get("itemName")),
        "ingredient": _first_text(
            item,
            "itemIngredient",
            "ingredient",
            "mainIngredient",
        ),
        "manufacturer": _clean_text(item.get("entpName")),
        "efficacy": _clean_text(item.get("efcyQesitm")),
        "usage": _clean_text(item.get("useMethodQesitm")),
        "cautions": cautions or None,
        "interaction": _clean_text(item.get("intrcQesitm")),
        "side_effects": _clean_text(item.get("seQesitm")),
        "storage": _clean_text(item.get("depositMethodQesitm")),
        "image_url": _clean_text(item.get("itemImage")),
        "source": "e약은요",
    }


def _first_text(item: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = _clean_text(item.get(key))
        if value:
            return value
    return None


def _clean_text(value: Any) -> str | None:
    if value is None:
        return None
    text = unescape(str(value))
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text or None
