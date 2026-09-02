import json
import logging
import re
from typing import Any
from urllib.parse import quote, unquote, urlencode
from xml.etree import ElementTree

import requests
from fastapi import HTTPException

from app.core.config import DUR_API_BASE_URL, DUR_API_KEY
from app.database import get_connection
from app.models.schemas import DurSyncRequest


logger = logging.getLogger(__name__)
TIMEOUT_SECONDS = 20
MFDS_DUR_SOURCE = "식약처 DUR 성분정보 OpenAPI"

ENDPOINTS = {
    "병용금기": "getUsjntTabooInfoList02",
    "연령금기": "getSpcifyAgrdeTabooInfoList02",
    "임부금기": "getPwnmTabooInfoList02",
    "효능군중복": "getEfcyDplctInfoList02",
}


def diagnose_dur_api_key(
    risk_type: str = "병용금기",
) -> dict[str, Any]:
    if risk_type not in ENDPOINTS:
        raise HTTPException(
            status_code=400,
            detail=f"지원하지 않는 DUR 유형입니다: {risk_type}",
        )
    if not DUR_API_KEY:
        return {
            "key_loaded": False,
            "risk_type": risk_type,
            "endpoint": ENDPOINTS[risk_type],
            "results": [],
        }

    endpoint = ENDPOINTS[risk_type]
    base_url = f"{DUR_API_BASE_URL}/{endpoint}"
    public_params = {
        "pageNo": 1,
        "numOfRows": 1,
        "type": "json",
    }
    safe_url = f"{base_url}?{urlencode(public_params)}"
    logger.info(
        "MFDS DUR diagnostic request key_loaded=%s url_without_serviceKey=%s",
        bool(DUR_API_KEY),
        safe_url,
    )

    decoded_key = unquote(DUR_API_KEY.strip())
    encoded_key = quote(decoded_key, safe="")
    results = [
        _diagnose_request(
            "decoding_key_via_params",
            base_url,
            params={"serviceKey": decoded_key, **public_params},
        ),
        _diagnose_request(
            "encoding_key_in_query",
            f"{base_url}?serviceKey={encoded_key}&{urlencode(public_params)}",
        ),
    ]
    return {
        "key_loaded": True,
        "key_contains_percent_encoding": "%" in DUR_API_KEY,
        "decoded_and_encoded_forms_differ": decoded_key != encoded_key,
        "risk_type": risk_type,
        "endpoint": endpoint,
        "base_url": base_url,
        "parameters_without_serviceKey": public_params,
        "results": results,
    }


def _diagnose_request(
    mode: str,
    url: str,
    *,
    params: dict[str, Any] | None = None,
) -> dict[str, Any]:
    try:
        response = requests.get(
            url,
            params=params,
            headers={
                "Accept": "application/json, application/xml, text/plain",
                "User-Agent": "alkong-yakong-dur-diagnostic/1.0",
            },
            timeout=TIMEOUT_SECONDS,
        )
        preview = _masked_preview(response.text)
        logger.info(
            "MFDS DUR diagnostic result mode=%s status=%s "
            "content_type=%s body=%s",
            mode,
            response.status_code,
            response.headers.get("content-type", ""),
            preview,
        )
        return {
            "mode": mode,
            "status_code": response.status_code,
            "content_type": response.headers.get("content-type", ""),
            "response_preview": preview,
        }
    except requests.RequestException as error:
        logger.warning(
            "MFDS DUR diagnostic failed mode=%s error=%s",
            mode,
            type(error).__name__,
        )
        return {
            "mode": mode,
            "error": type(error).__name__,
        }


def sync_mfds_dur(request: DurSyncRequest) -> dict[str, Any]:
    logger.info("DUR_API_KEY loaded = %s", bool(DUR_API_KEY))
    unknown = sorted(set(request.types) - set(ENDPOINTS))
    if unknown:
        raise HTTPException(
            status_code=400,
            detail=f"지원하지 않는 DUR 유형입니다: {', '.join(unknown)}",
        )

    conn = get_connection()
    try:
        cursor = conn.cursor()
        result = {
            "source": MFDS_DUR_SOURCE,
            "types": {},
            "total_fetched": 0,
            "inserted": 0,
            "updated": 0,
            "skipped": 0,
            "skipped_missing_key": 0,
        }
        for risk_type in request.types:
            if not DUR_API_KEY:
                result["types"][risk_type] = {
                    "status": "skipped_missing_key",
                    "total_fetched": 0,
                    "inserted": 0,
                    "updated": 0,
                    "skipped": 0,
                    "skipped_missing_key": 1,
                }
                result["skipped_missing_key"] += 1
                continue
            stats = _sync_type(
                cursor,
                risk_type,
                api_key=DUR_API_KEY,
                page_size=request.page_size,
                max_pages=request.max_pages,
            )
            result["types"][risk_type] = stats
            for key in (
                "total_fetched",
                "inserted",
                "updated",
                "skipped",
                "skipped_missing_key",
            ):
                result[key] += stats[key]
        conn.commit()
        return result
    except HTTPException:
        conn.rollback()
        raise
    except Exception as error:
        conn.rollback()
        logger.warning("MFDS DUR synchronization failed: %s", error, exc_info=True)
        raise HTTPException(
            status_code=502,
            detail="식약처 DUR 데이터 동기화에 실패했습니다.",
        ) from error
    finally:
        conn.close()


def _sync_type(
    cursor,
    risk_type: str,
    *,
    api_key: str,
    page_size: int,
    max_pages: int | None,
) -> dict[str, int]:
    page = 1
    stats = {
        "total_fetched": 0,
        "inserted": 0,
        "updated": 0,
        "skipped": 0,
        "skipped_missing_key": 0,
    }
    while True:
        items, total_count = _fetch_page(
            ENDPOINTS[risk_type],
            api_key=api_key,
            page=page,
            page_size=page_size,
        )
        stats["total_fetched"] += len(items)
        for item in items:
            normalized = _normalize_item(risk_type, item)
            if not normalized:
                stats["skipped"] += 1
                continue
            action = _upsert_taboo(cursor, normalized)
            stats[action] += 1

        if not items or page * page_size >= total_count:
            break
        if max_pages is not None and page >= max_pages:
            break
        page += 1
    return stats


def _fetch_page(
    endpoint: str,
    *,
    api_key: str,
    page: int,
    page_size: int,
) -> tuple[list[dict[str, Any]], int]:
    url = f"{DUR_API_BASE_URL}/{endpoint}"
    try:
        response = requests.get(
            url,
            params={
                # requests performs URL encoding, so normalize an Encoding key
                # back to its decoded form to avoid double encoding.
                "serviceKey": unquote(api_key.strip()),
                "pageNo": page,
                "numOfRows": page_size,
                "type": "json",
            },
            timeout=TIMEOUT_SECONDS,
        )
    except requests.RequestException as error:
        logger.warning(
            "MFDS DUR request failed endpoint=%s error=%s",
            endpoint,
            type(error).__name__,
        )
        raise HTTPException(
            status_code=502,
            detail="식약처 DUR API에 연결할 수 없습니다.",
        ) from error

    if not response.ok:
        _log_external_response(endpoint, response)
        raise HTTPException(
            status_code=502,
            detail=f"식약처 DUR API 호출 실패 (외부 HTTP {response.status_code})",
        )

    try:
        payload = _parse_response(response)
    except (ValueError, ElementTree.ParseError) as error:
        _log_external_response(endpoint, response)
        raise HTTPException(
            status_code=502,
            detail="식약처 DUR API 응답 형식을 해석할 수 없습니다.",
        ) from error

    header = payload.get("header") or payload.get("response", {}).get("header", {})
    result_code = str(header.get("resultCode") or "00")
    if result_code not in {"00", "0"}:
        _log_external_response(endpoint, response)
        raise HTTPException(
            status_code=502,
            detail=f"식약처 DUR API 오류: {header.get('resultMsg') or result_code}",
        )
    body = payload.get("body") or payload.get("response", {}).get("body", {})
    items = body.get("items", {}) if isinstance(body, dict) else {}
    items = _extract_items(items)
    return (
        items,
        int(body.get("totalCount") or 0),
    )


def _extract_items(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        value = value.get("item", value)
    if isinstance(value, dict):
        return [value]
    if not isinstance(value, list):
        return []

    result = []
    for entry in value:
        if isinstance(entry, dict) and isinstance(entry.get("item"), dict):
            result.append(entry["item"])
        elif isinstance(entry, dict):
            result.append(entry)
    return result


def _parse_response(response: requests.Response) -> dict[str, Any]:
    content_type = response.headers.get("content-type", "").lower()
    text = response.text.lstrip()
    if "json" in content_type or text.startswith(("{", "[")):
        payload = response.json()
        if not isinstance(payload, dict):
            raise ValueError("DUR response root is not an object.")
        return payload
    if "xml" in content_type or text.startswith("<"):
        return _xml_to_payload(response.text)
    raise ValueError(f"Unsupported DUR response content type: {content_type}")


def _xml_to_payload(text: str) -> dict[str, Any]:
    root = ElementTree.fromstring(text)
    error_message = root.findtext(".//returnAuthMsg") or root.findtext(
        ".//errMsg"
    )
    if error_message:
        return {
            "header": {
                "resultCode": root.findtext(".//returnReasonCode") or "ERROR",
                "resultMsg": error_message,
            },
            "body": {},
        }

    header_node = root.find(".//header")
    body_node = root.find(".//body")
    header = (
        {child.tag: child.text for child in header_node}
        if header_node is not None
        else {}
    )
    body: dict[str, Any] = {}
    if body_node is not None:
        for child in body_node:
            if child.tag == "items":
                body["items"] = {
                    "item": [
                        {field.tag: field.text for field in item}
                        for item in child.findall("item")
                    ]
                }
            else:
                body[child.tag] = child.text
    return {"header": header, "body": body}


def _log_external_response(
    endpoint: str,
    response: requests.Response,
) -> None:
    preview = _masked_preview(response.text)
    logger.warning(
        "MFDS DUR response error endpoint=%s status=%s content_type=%s body=%s",
        endpoint,
        response.status_code,
        response.headers.get("content-type", ""),
        preview,
    )


def _masked_preview(value: str) -> str:
    return re.sub(
        r"(?i)(serviceKey=)[^&\s<]+",
        r"\1***",
        value[:500].replace("\r", " ").replace("\n", " "),
    )


def _normalize_item(
    risk_type: str,
    item: dict[str, Any],
) -> dict[str, Any] | None:
    # 식약처는 DEL_YN 에 Y/N 또는 정상/삭제를 씀. 삭제 행은 넣지 않음.
    del_yn = str(item.get("DEL_YN") or "N").strip()
    if del_yn.upper() in {"Y", "삭제", "DELETE", "DELETED"} or del_yn == "삭제":
        return None

    ingredient_a = _first(
        item,
        "INGR_KOR_NAME",
        "INGR_NAME",
        "INGR_ENG_NAME",
    )
    if not ingredient_a:
        return None

    ingredient_b = None
    ingredient_b_code = None
    if risk_type == "병용금기":
        ingredient_b = _first(
            item,
            "MIXTURE_INGR_KOR_NAME",
            "MIXTURE_INGR_ENG_NAME",
        )
        ingredient_b_code = _first(item, "MIXTURE_INGR_CODE")
        if not ingredient_b:
            return None
    elif risk_type == "효능군중복":
        # 같은 EFFECT_CODE 끼리 겹칠 때만 주의 → 분석 시 그룹 키로 사용
        ingredient_b = _first(item, "EFFECT_CODE", "SERS_NAME", "CLASS_NAME")

    min_age, max_age = _parse_age_base(
        _first(item, "AGE_BASE") if risk_type == "연령금기" else None
    )
    external_id = _first(item, "DUR_SEQ")
    if not external_id:
        external_id = "|".join(
            filter(
                None,
                (
                    risk_type,
                    _first(item, "INGR_CODE"),
                    ingredient_b_code,
                    _first(item, "NOTIFICATION_DATE"),
                ),
            )
        )

    return {
        "ingredient_a": ingredient_a,
        "ingredient_b": ingredient_b,
        "taboo_type": risk_type,
        "severity": (
            "HIGH" if risk_type in {"병용금기", "효능군중복"} else "MEDIUM"
        ),
        "description": _first(item, "PROHBT_CONTENT", "REMARK")
        or f"식약처 {risk_type} 정보입니다.",
        "source": MFDS_DUR_SOURCE,
        "external_id": external_id,
        "ingredient_a_code": _first(item, "INGR_CODE"),
        "ingredient_b_code": ingredient_b_code,
        "min_age": min_age,
        "max_age": max_age,
        "pregnancy_grade": (
            _first(item, "GRADE") if risk_type == "임부금기" else None
        ),
        "notification_date": _first(item, "NOTIFICATION_DATE"),
        "raw_json": json.dumps(item, ensure_ascii=False),
    }


def _upsert_taboo(cursor, item: dict[str, Any]) -> str:
    existing = cursor.execute(
        """
        SELECT id FROM dur_taboo
        WHERE source = ? AND taboo_type = ? AND external_id = ?
        """,
        (item["source"], item["taboo_type"], item["external_id"]),
    ).fetchone()
    cursor.execute(
        """
        INSERT INTO dur_taboo (
            ingredient_a, ingredient_b, taboo_type, severity, description,
            source, external_id, ingredient_a_code, ingredient_b_code,
            min_age, max_age, pregnancy_grade, notification_date, raw_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(source, taboo_type, external_id) WHERE external_id IS NOT NULL
        DO UPDATE SET
            ingredient_a = excluded.ingredient_a,
            ingredient_b = excluded.ingredient_b,
            severity = excluded.severity,
            description = excluded.description,
            ingredient_a_code = excluded.ingredient_a_code,
            ingredient_b_code = excluded.ingredient_b_code,
            min_age = excluded.min_age,
            max_age = excluded.max_age,
            pregnancy_grade = excluded.pregnancy_grade,
            notification_date = excluded.notification_date,
            raw_json = excluded.raw_json,
            updated_at = CURRENT_TIMESTAMP
        """,
        (
            item["ingredient_a"],
            item["ingredient_b"],
            item["taboo_type"],
            item["severity"],
            item["description"],
            item["source"],
            item["external_id"],
            item["ingredient_a_code"],
            item["ingredient_b_code"],
            item["min_age"],
            item["max_age"],
            item["pregnancy_grade"],
            item["notification_date"],
            item["raw_json"],
        ),
    )
    return "updated" if existing else "inserted"


def _parse_age_base(value: str | None) -> tuple[int | None, int | None]:
    """AGE_BASE → (min_age, max_age) 금기 연령대. 파싱 불가면 (None, None)."""
    if not value:
        return None, None
    text = str(value).strip()

    # 개월/주: 연 단위로는 영아(0세)만 해당. 성인 오탐 방지.
    month_match = re.search(r"(\d+)\s*개월", text)
    week_match = re.search(r"(\d+)\s*주", text)
    if month_match or week_match:
        if "이상" in text or "초과" in text:
            months = int((month_match or week_match).group(1))
            if week_match and not month_match:
                months = max(1, int(week_match.group(1)) // 4)
            min_age = max(0, months // 12)
            if "초과" in text and months % 12 == 0:
                min_age += 1
            return min_age, None
        # 미만/이하/그 외 → 만 0세(1세 미만)만 금기로 본다
        return None, 0

    match = re.search(r"(\d+)\s*세", text)
    if not match:
        return None, None
    age = int(match.group(1))
    if "이상" in text or "초과" in text:
        return age + (1 if "초과" in text else 0), None
    if "미만" in text:
        return None, max(age - 1, 0)
    # "N세 이하" 및 숫자만 있는 경우 → max_age = N
    return None, age


def _first(item: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = item.get(key)
        if value is not None and str(value).strip():
            return str(value).strip()
    return None
