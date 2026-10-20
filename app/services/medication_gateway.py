"""Read the medication source of truth; fail closed instead of using the wrong DB."""
import requests
from urllib.parse import quote
from fastapi import HTTPException
from app.core.config import MEDICATION_FEATURE_BASE_URL, MEDICATION_FEATURE_TIMEOUT_SECONDS, APP_ENV
from app.core.auth import service_headers


def medication_get(user_id, suffix, *, params=None, local=None):
    if not MEDICATION_FEATURE_BASE_URL:
        if APP_ENV != "production" and local:
            return local()
        raise HTTPException(503, "약 기록 서버 연결 설정이 필요해요.")
    try:
        response = requests.get(MEDICATION_FEATURE_BASE_URL + "/api/v1/users/" + quote(user_id, safe="") + suffix,
                                params=params, headers=service_headers(user_id), timeout=MEDICATION_FEATURE_TIMEOUT_SECONDS)
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise ValueError("Invalid medication response")
        return payload
    except (requests.RequestException, ValueError):
        raise HTTPException(503, "환자의 약 기록을 불러오지 못했어요. 잠시 후 다시 확인해 주세요.")
