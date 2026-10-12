"""Signed, expiring sessions and server-side patient/guardian access checks.

Both services must share ALKONGYAKONG_AUTH_SECRET. The medication service must
set SERVICE_ROLE=medication and AUTH_AUTHORITY_BASE_URL to the main service.
Production fails closed when credentials/configuration are missing.
"""
import base64
import hashlib
import hmac
import json
import os
import time
from contextvars import ContextVar
from urllib.parse import quote

import requests
from fastapi import HTTPException, Request, Depends
from fastapi.security import HTTPBearer

from app.core.config import APP_ENV
from app.database import get_connection

_token = ContextVar("access_token", default="")
_bearer_scheme = HTTPBearer(auto_error=False)


def enforced():
    return os.getenv("AUTH_ENFORCED", str(APP_ENV == "production" or bool(os.getenv("RENDER")))).lower() == "true"


def _secret():
    value = os.getenv("ALKONGYAKONG_AUTH_SECRET", "")
    if len(value) < 32:
        if enforced():
            raise HTTPException(503, "서버 로그인 설정을 확인해야 합니다.")
        return "development-only-never-use-in-production"
    return value


def _b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def issue_token(user_id, role, *, service=False):
    now = int(time.time())
    payload = {"sub": user_id, "role": role.upper(), "iat": now,
               "exp": now + (60 if service else 7 * 24 * 3600),
               "iss": "alkongyakong", "aud": "alkongyakong-api", "service": service}
    signing = _b64(b'{"alg":"HS256","typ":"JWT"}') + "." + _b64(json.dumps(payload).encode())
    return signing + "." + _b64(hmac.new(_secret().encode(), signing.encode(), hashlib.sha256).digest())


def verify_token(token):
    try:
        header, payload, signature = token.split(".")
        signing = header + "." + payload
        expected = _b64(hmac.new(_secret().encode(), signing.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(signature, expected):
            raise ValueError()
        decode = lambda s: json.loads(base64.urlsafe_b64decode(s + "=" * (-len(s) % 4)))
        if decode(header) != {"alg": "HS256", "typ": "JWT"}:
            raise ValueError()
        claims = decode(payload)
        if (claims.get("iss") != "alkongyakong" or claims.get("aud") != "alkongyakong-api"
                or not isinstance(claims.get("exp"), int) or claims["exp"] <= time.time()
                or claims.get("role") not in {"PATIENT", "GUARDIAN", "SERVICE"}
                or not isinstance(claims.get("sub"), str) or not claims["sub"]):
            raise ValueError()
        return claims
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(401, "로그인이 만료되었어요. 다시 로그인해 주세요.")


def service_headers(user_id):
    return {"Authorization": "Bearer " + issue_token(user_id, "SERVICE", service=True)}


def current_actor():
    token = _token.get()
    return verify_token(token) if token else None


def _bearer(request):
    value = request.headers.get("authorization", "")
    if not value.startswith("Bearer "):
        raise HTTPException(401, "로그인이 필요해요.")
    return value[7:]


def can_access(claims, target, *, write=False):
    conn = get_connection()
    try:
        actor = conn.execute("SELECT id, role, phone FROM users WHERE id=?", (claims["sub"],)).fetchone()
        if not actor or str(actor["role"]).upper() != claims["role"]:
            return False
        if target == claims["sub"]:
            return True
        if claims["role"] != "GUARDIAN":
            return False
        linked = conn.execute(
            "SELECT 1 FROM guardians WHERE user_id=? AND guardian_user_id=? AND UPPER(status)='ACCEPTED'",
            (target, claims["sub"]),
        ).fetchone() is not None
        if linked:
            return True
        if enforced():
            return False  # A claimed phone number is not proof of ownership.
        from app.services.account_lookup import phone_digits
        phone = phone_digits(actor["phone"])
        return bool(phone) and any(phone_digits(row["phone"]) == phone for row in conn.execute(
            "SELECT phone FROM guardians WHERE user_id=? AND guardian_user_id IS NULL AND UPPER(status)='ACCEPTED'",
            (target,),
        ))
    finally:
        conn.close()


async def authorize_request(request: Request, credentials=Depends(_bearer_scheme)):
    path = request.url.path
    if path == "/api/v1/users" and request.method == "GET":
        # This endpoint retains its separate mandatory administrator key.
        yield
        return
    if enforced() and (path.startswith("/api/v1/dur/sync") or path.startswith("/api/v1/biosignal-test")):
        from app.routes.users import _require_admin
        _require_admin(request.headers.get("x-admin-key"))
        yield
        return
    if not enforced() or path in {"/api/v1/users", "/api/v1/users/login"} and request.method == "POST":
        yield
        return
    # Public official drug information has no personal data.
    if request.method == "GET" and (path == "/api/v1/drugs/search" or path == "/api/v1/medicines/lookup"
            or path.startswith("/api/v1/drug-explain/") and path != "/api/v1/drug-explain/cache-context"):
        yield
        return
    token = _bearer(request)
    claims = verify_token(token)
    context = _token.set(token)
    try:
        params = request.path_params
        raw = await request.body() if request.method in {"POST", "PATCH", "PUT"} else b""
        try:
            body = json.loads(raw) if raw else {}
        except ValueError:
            raise HTTPException(400, "요청 본문이 올바른 JSON이 아닙니다.")
        if not isinstance(body, dict):
            raise HTTPException(422, "요청 본문은 JSON 객체여야 합니다.")
        target = params.get("user_id") or params.get("guardian_user_id") or body.get("user_id") or body.get("guardian_user_id") or request.query_params.get("user_id")
        is_service = claims.get("service") is True and claims["role"] == "SERVICE"
        if is_service:
            consultation = path == "/api/v1/dur/analyze" and body.get("analysis_purpose") == "consultation"
            if target != claims["sub"] or (request.method != "GET" and not consultation and path not in {
                f"/api/v1/internal/users/{target}",
            }):
                raise HTTPException(403, "허용되지 않은 서버 요청입니다.")
            if os.getenv("SERVICE_ROLE", "main") == "medication" and consultation:
                authority = os.getenv("AUTH_AUTHORITY_BASE_URL", "").rstrip("/")
                if not authority:
                    raise HTTPException(503, "서버 권한 확인 설정이 필요합니다.")
                try:
                    response = requests.get(authority + "/api/v1/users/" + quote(target, safe=""), headers=service_headers(target), timeout=10)
                    response.raise_for_status()
                    profile = response.json()
                    if profile.get("id") != target:
                        raise ValueError("Identity mismatch")
                    from app.services.medication_user_service import sync_medication_health
                    sync_medication_health(target, profile)
                except (requests.RequestException, ValueError, AttributeError):
                    raise HTTPException(503, "환자의 건강정보를 확인하지 못했어요.")
            yield
            return
        if (path.startswith("/api/v1/guardians/accounts/") or path == "/api/v1/guardians/link-requests") and claims["role"] != "GUARDIAN":
            raise HTTPException(403, "보호자 계정에서만 할 수 있어요.")
        # Own profile changes, completion logs and sensor writes cannot be performed by a guardian.
        own_only = (path.startswith("/api/v1/medication-logs") or path == "/api/v1/biosignal/heart-rate"
                    or path.startswith("/api/v1/guardians/users/")
                    or request.method in {"PATCH", "DELETE"} and path == f"/api/v1/users/{target}")
        if own_only and target != claims["sub"]:
            raise HTTPException(403, "본인 계정에서만 할 수 있어요.")
        if params.get("guardian_id"):
            conn = get_connection()
            try:
                link = conn.execute("SELECT user_id, guardian_user_id FROM guardians WHERE id=?", (params["guardian_id"],)).fetchone()
            finally:
                conn.close()
            if not link or claims["sub"] not in {link["user_id"], link["guardian_user_id"]}:
                raise HTTPException(403, "이 연결을 변경할 권한이 없어요.")
            if request.method == "PATCH" and claims["sub"] != link["user_id"]:
                raise HTTPException(403, "환자만 연결을 수락할 수 있어요.")
            yield
            return
        if path.startswith("/api/v1/dur/sync") or path.startswith("/api/v1/biosignal-test"):
            raise HTTPException(403, "운영자 전용 기능입니다.")
        if target is None:
            raise HTTPException(403, "요청 대상을 확인하지 못했어요.")
        if os.getenv("SERVICE_ROLE", "main") == "medication":
            authority = os.getenv("AUTH_AUTHORITY_BASE_URL", "").rstrip("/")
            if not authority:
                raise HTTPException(503, "서버 권한 확인 설정이 필요합니다.")
            try:
                response = requests.get(authority + "/api/v1/auth/access", params={"user_id": target},
                                        headers={"Authorization": "Bearer " + token}, timeout=10)
                if response.status_code >= 500:
                    raise HTTPException(503, "지금은 접근 권한을 확인하지 못했어요.")
                if response.status_code == 401:
                    raise HTTPException(401, "다시 로그인해 주세요.")
                if response.status_code != 200 or response.json().get("allowed") is not True:
                    raise HTTPException(403, "연결된 환자의 기록만 볼 수 있어요.")
                profile_response = requests.get(authority + "/api/v1/users/" + quote(target, safe=""),
                                                headers=service_headers(target), timeout=10)
                if profile_response.status_code != 200:
                    raise HTTPException(503, "환자의 건강정보를 확인하지 못했어요.")
                profile = profile_response.json()
                if not isinstance(profile, dict) or profile.get("id") != target:
                    raise HTTPException(503, "환자의 건강정보를 확인하지 못했어요.")
                from app.services.medication_user_service import sync_medication_health
                sync_medication_health(target, profile)
            except (requests.RequestException, ValueError):
                raise HTTPException(503, "지금은 접근 권한을 확인하지 못했어요.")
        elif not can_access(claims, target):
            raise HTTPException(403, "본인 또는 연결된 환자의 기록만 볼 수 있어요.")
        yield
    finally:
        _token.reset(context)
