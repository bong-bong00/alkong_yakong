import requests
from fastapi import HTTPException
from app.core.config import MFDS_SERVICE_KEY, MFDS_E_DRUG_BASE_URL

TIMEOUT_SECONDS = 10

def search_drug_info_by_name(name: str, page_no: int = 1, num_of_rows: int = 10) -> dict:
    if not MFDS_SERVICE_KEY:
        raise HTTPException(status_code=500, detail="MFDS_SERVICE_KEY가 설정되지 않았습니다.")

    params = {
        "ServiceKey": MFDS_SERVICE_KEY,
        "pageNo": page_no,
        "numOfRows": num_of_rows,
        "itemName": name,
        "type": "json",
    }

    try:
        response = requests.get(MFDS_E_DRUG_BASE_URL, params=params, timeout=TIMEOUT_SECONDS)
        response.raise_for_status()
        data = response.json()
    except requests.exceptions.Timeout:
        raise HTTPException(status_code=504, detail="식약처 API 타임아웃")
    except requests.exceptions.RequestException as e:
        raise HTTPException(status_code=502, detail=f"식약처 API 호출 실패: {str(e)}")
    except ValueError:
        raise HTTPException(status_code=502, detail="식약처 API 응답이 JSON 형식이 아닙니다.")

    body = data.get("body", {})
    items = body.get("items", [])

    if isinstance(items, dict):
        items = [items]

    normalized = []
    for item in items:
        normalized.append({
            "company_name": item.get("entpName"),
            "drug_name": item.get("itemName"),
            "item_seq": item.get("itemSeq"),
            "effect": item.get("efcyQesitm"),
            "usage": item.get("useMethodQesitm"),
            "warning_before_use": item.get("atpnWarnQesitm"),
            "warning_general": item.get("atpnQesitm"),
            "interaction": item.get("intrcQesitm"),
            "side_effect": item.get("seQesitm"),
            "storage": item.get("depositMethodQesitm"),
            "image": item.get("itemImage"),
        })

    return {
        "query": name,
        "count": len(normalized),
        "items": normalized
    }