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
        "serviceKey": E_DRUG_API_KEY,
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
        payload = _load_e_drug_payload(response, operation="fetch")
        _log_e_drug_response(response, payload, operation="fetch")
        response.raise_for_status()
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

    try:
        exact_items = _request_drug_items(
            name.strip(),
            page_no=page_no,
            num_of_rows=num_of_rows,
        )
        exact_key = _compact_drug_name(name)
        exact_matches = [
            item
            for item in exact_items
            if _compact_drug_name(item.get("itemName")) == exact_key
        ]
        if exact_matches:
            normalized = [_normalize_item(item) for item in exact_matches]
            return {
                "query": name,
                "count": len(normalized),
                "items": normalized,
                "match_type": "exact",
            }

        normalized_query = _normalize_drug_search_name(name)
        partial_items = exact_items
        if normalized_query and normalized_query != exact_key:
            partial_items = _request_drug_items(
                normalized_query,
                page_no=page_no,
                num_of_rows=num_of_rows,
            )

        scored_matches = []
        for item in partial_items:
            candidate_name = _normalize_drug_search_name(item.get("itemName"))
            if not normalized_query or normalized_query not in candidate_name:
                continue
            startswith = candidate_name.startswith(normalized_query)
            length_ratio = len(normalized_query) / max(len(candidate_name), 1)
            match_score = (
                80.0 + (20.0 * length_ratio)
                if startswith
                else 50.0 + (20.0 * length_ratio)
            )
            scored_matches.append(
                (
                    0 if startswith else 1,
                    len(_compact_drug_name(item.get("itemName"))),
                    _compact_drug_name(item.get("itemName")),
                    match_score,
                    item,
                )
            )
        scored_matches.sort(key=lambda match: match[:3])
        partial_matches = [match[4] for match in scored_matches]
        if scored_matches:
            best_match = scored_matches[0]
            logger.info(
                "match_type=partial matched_name=%s match_score=%.2f",
                best_match[4].get("itemName"),
                best_match[3],
            )
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

    normalized = [_normalize_item(item) for item in partial_matches]
    response = {"query": name, "count": len(normalized), "items": normalized}
    if normalized:
        response["match_type"] = "partial"
    return response


def _request_drug_items(
    query: str,
    *,
    page_no: int,
    num_of_rows: int,
) -> list[dict[str, Any]]:
    params = {
        "serviceKey": E_DRUG_API_KEY,
        "pageNo": page_no,
        "numOfRows": num_of_rows,
        "itemName": query,
        "type": "json",
    }
    response = requests.get(
        E_DRUG_BASE_URL,
        params=params,
        timeout=TIMEOUT_SECONDS,
    )
    payload = _load_e_drug_payload(response, operation="search")
    _log_e_drug_response(response, payload, operation="search")
    response.raise_for_status()
    return _extract_items(payload)


def _load_e_drug_payload(
    response: requests.Response,
    *,
    operation: str,
) -> dict[str, Any]:
    try:
        payload = response.json()
    except ValueError:
        logger.warning(
            "e약은요 response operation=%s outcome=invalid_json status=%s "
            "content_type=%s",
            operation,
            response.status_code,
            response.headers.get("content-type", ""),
        )
        raise
    if not isinstance(payload, dict):
        logger.warning(
            "e약은요 response operation=%s outcome=invalid_structure status=%s "
            "content_type=%s payload_type=%s",
            operation,
            response.status_code,
            response.headers.get("content-type", ""),
            type(payload).__name__,
        )
        raise TypeError("e약은요 response root must be an object")
    return payload


def _log_e_drug_response(
    response: requests.Response,
    payload: dict[str, Any],
    *,
    operation: str,
) -> None:
    envelope = payload.get("response") if isinstance(payload, dict) else None
    root = envelope if isinstance(envelope, dict) else payload
    header = root.get("header", {}) if isinstance(root, dict) else {}
    result_code = header.get("resultCode") if isinstance(header, dict) else None
    result_message = header.get("resultMsg") if isinstance(header, dict) else None
    items = _extract_items(payload)

    normalized_message = str(result_message or "").casefold()
    auth_terms = (
        "service key",
        "authentication",
        "not registered",
        "access denied",
        "인증",
        "권한",
    )
    if response.status_code in {401, 403} or any(
        term in normalized_message for term in auth_terms
    ):
        outcome = "authentication_or_permission_failure"
    elif not response.ok or result_code not in (None, "00"):
        outcome = "api_error"
    elif not items:
        outcome = "no_items"
    else:
        outcome = "success"

    log = logger.warning if outcome.endswith("failure") or outcome == "api_error" else logger.info
    log(
        "e약은요 response operation=%s outcome=%s status=%s content_type=%s "
        "result_code=%s result_message=%s items_present=%s item_count=%d",
        operation,
        outcome,
        response.status_code,
        response.headers.get("content-type", ""),
        result_code,
        result_message,
        bool(items),
        len(items),
    )


def _compact_drug_name(value: Any) -> str:
    return re.sub(r"\s+", "", str(value or "")).casefold()


def _normalize_drug_search_name(value: Any) -> str:
    text = _compact_drug_name(value)
    text = re.sub(r"\d+(?:\.\d+)?(?:mg|ml)", "", text, flags=re.IGNORECASE)
    text = re.sub(r"(?:mg|ml)", "", text, flags=re.IGNORECASE)
    for dosage_form in ("필름코팅정", "연질캡슐", "캡슐", "정"):
        if text.endswith(dosage_form):
            text = text[: -len(dosage_form)]
            break
    return text


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
