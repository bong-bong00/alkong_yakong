"""Short-lived, purpose-bound credentials shared by the two Render services.

Only the account service issues patient tokens. The medication service verifies
their signature locally and asks the account service about guardian consent.
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
import time
from typing import Any
from urllib.parse import quote

import requests
from fastapi import HTTPException, Request

from app.database import get_connection

_AUDIENCE = "alkong-yakong"
_ACCESS_TTL_SECONDS = 7 * 24 * 60 * 60
_SERVICE_TTL_SECONDS = 60
_READABLE_BY_GUARDIAN = {
    "medicines", "today-medicines", "medication-history",
    "medication-calendar", "medication-overview", "dashboard", "prescriptions",
    "dur", "biosignal", "notifications",
}


def auth_enforced() -> bool:
    return os.getenv("AUTH_ENFORCED", "false").strip().lower() == "true"


def service_role() -> str:
    return os.getenv("SERVICE_ROLE", "").strip().lower()


def validate_auth_configuration() -> None:
    """Never start a Render instance that silently accepts unsigned requests."""
    if not os.getenv("RENDER") and not auth_enforced():
        return
    if not auth_enforced():
        raise RuntimeError("AUTH_ENFORCED must be true on Render")
    if service_role() not in {"main", "medication"}:
        raise RuntimeError("SERVICE_ROLE must be main or medication")
    if len(os.getenv("ALKONGYAKONG_AUTH_SECRET", "")) < 32:
        raise RuntimeError("ALKONGYAKONG_AUTH_SECRET must be at least 32 characters")
    db_path = os.getenv("ALKONGYAKONG_DB_PATH", "")
    if not db_path or not os.path.isabs(db_path):
        raise RuntimeError("ALKONGYAKONG_DB_PATH must be an absolute persistent path")
    required_url = (
        "AUTH_AUTHORITY_BASE_URL" if service_role() == "medication"
        else "MEDICATION_FEATURE_BASE_URL"
    )
    if not os.getenv(required_url, "").strip().startswith("https://"):
        raise RuntimeError(f"{required_url} must be an HTTPS URL")


def _b64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _unb64(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def issue_token(
    subject: str, *, role: str, kind: str = "access", target: str | None = None,
    scope: str | None = None,
) -> tuple[str, int]:
    secret = os.getenv("ALKONGYAKONG_AUTH_SECRET", "")
    if len(secret) < 32:
        raise RuntimeError("Authentication secret is not configured")
    now = int(time.time())
    lifetime = _ACCESS_TTL_SECONDS if kind == "access" else _SERVICE_TTL_SECONDS
    payload = {
        "aud": _AUDIENCE, "sub": subject, "role": role.lower(),
        "kind": kind, "iat": now, "exp": now + lifetime,
    }
    if target:
        payload["target"] = target
    if scope:
        payload["scope"] = scope
    encoded = _b64(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode())
    signature = _b64(hmac.new(secret.encode(), encoded.encode(), hashlib.sha256).digest())
    return f"{encoded}.{signature}", lifetime


def verify_token(raw: str) -> dict[str, Any]:
    secret = os.getenv("ALKONGYAKONG_AUTH_SECRET", "")
    if len(secret) < 32:
        raise HTTPException(status_code=503, detail="인증 설정이 준비되지 않았어요.")
    try:
        if len(raw) > 4096:
            raise ValueError("length")
        encoded, signature = raw.split(".")
        expected = _b64(hmac.new(secret.encode(), encoded.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(signature, expected):
            raise ValueError("signature")
        payload = json.loads(_unb64(encoded))
        if (
            not isinstance(payload, dict)
            or payload.get("aud") != _AUDIENCE
            or not isinstance(payload.get("sub"), str)
            or not payload["sub"]
            or payload.get("role") not in {"patient", "guardian", "service"}
            or payload.get("kind") not in {"access", "service"}
            or (payload["kind"] == "service") != (payload["role"] == "service")
            or not isinstance(payload.get("exp"), int)
            or not isinstance(payload.get("iat"), int)
            or payload["iat"] > int(time.time()) + 30
            or payload["exp"] <= int(time.time())
            or payload["exp"] <= payload["iat"]
            or payload["exp"] - payload["iat"] > (
                _ACCESS_TTL_SECONDS if payload["kind"] == "access" else _SERVICE_TTL_SECONDS
            )
        ):
            raise ValueError("claims")
        return payload
    except (ValueError, TypeError, KeyError, UnicodeDecodeError, json.JSONDecodeError):
        raise HTTPException(status_code=401, detail="로그인이 만료되었거나 올바르지 않아요.") from None


def load_authority_identity(user_id: str) -> dict[str, Any]:
    """Read current identity; deleted accounts do not retain access until expiry."""
    if service_role() == "main":
        conn = get_connection()
        try:
            row = conn.execute(
                """SELECT id, name, role, birth_date, gender, is_pregnant,
                          pregnancy_status FROM users WHERE id = ?""", (user_id,),
            ).fetchone()
            if row is None:
                raise HTTPException(status_code=401, detail="다시 로그인해 주세요.")
            return dict(row)
        finally:
            conn.close()
    authority = os.getenv("AUTH_AUTHORITY_BASE_URL", "").rstrip("/")
    if not authority.startswith("https://"):
        raise HTTPException(status_code=503, detail="사용자 권한을 확인할 수 없어요.")
    token, _ = issue_token("medication", role="service", kind="service",
                           target=user_id, scope="identity_read")
    try:
        response = requests.get(
            f"{authority}/api/v1/auth/identity/{quote(user_id, safe='')}",
            headers={"Authorization": f"Bearer {token}"}, timeout=5,
        )
        if response.status_code in {401, 404}:
            raise HTTPException(status_code=401, detail="다시 로그인해 주세요.")
        response.raise_for_status()
        identity = response.json()
        if not isinstance(identity, dict) or identity.get("id") != user_id:
            raise ValueError("identity")
        return identity
    except (requests.RequestException, ValueError):
        raise HTTPException(status_code=503, detail="사용자 권한을 확인할 수 없어요.") from None


def provision_medication_identity(identity: dict[str, Any]) -> None:
    """Explicit authenticated synchronization, never a URL-only read side effect."""
    if service_role() != "medication":
        return
    conn = get_connection()
    try:
        conn.execute(
            """INSERT INTO users (id, name, role, birth_date, gender,
                                  is_pregnant, pregnancy_status)
               VALUES (?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(id) DO UPDATE SET
                 name=excluded.name, role=excluded.role,
                 birth_date=COALESCE(excluded.birth_date, users.birth_date),
                 gender=COALESCE(excluded.gender, users.gender),
                 is_pregnant=excluded.is_pregnant,
                 pregnancy_status=excluded.pregnancy_status""",
            (identity["id"], identity["name"], identity["role"],
             identity.get("birth_date"), identity.get("gender"),
             int(bool(identity.get("is_pregnant"))), identity.get("pregnancy_status")),
        )
        conn.commit()
    finally:
        conn.close()


def _linked_guardian_locally(guardian_id: str, patient_id: str) -> bool:
    conn = get_connection()
    try:
        return conn.execute(
            """SELECT 1 FROM guardians WHERE guardian_user_id = ? AND user_id = ?
               AND status = 'ACCEPTED' AND consent_verified_at IS NOT NULL""",
            (guardian_id, patient_id),
        ).fetchone() is not None
    finally:
        conn.close()


def _linked_guardian_remotely(guardian_id: str, patient_id: str) -> bool:
    authority = os.getenv("AUTH_AUTHORITY_BASE_URL", "").rstrip("/")
    if not authority.startswith("https://"):
        raise HTTPException(status_code=503, detail="보호자 권한을 확인할 수 없어요.")
    token, _ = issue_token(
        guardian_id, role="service", kind="service", target=patient_id,
        scope="guardian_link_check",
    )
    try:
        response = requests.get(
            f"{authority}/api/v1/guardians/internal/authorization",
            params={"guardian_id": guardian_id, "patient_id": patient_id},
            headers={"Authorization": f"Bearer {token}"}, timeout=5,
        )
        response.raise_for_status()
        return response.json().get("allowed") is True
    except (requests.RequestException, ValueError, AttributeError):
        raise HTTPException(status_code=503, detail="보호자 권한을 확인할 수 없어요.") from None


async def _guardian_can_read(guardian_id: str, patient_id: str) -> bool:
    if service_role() == "main":
        return await asyncio.to_thread(_linked_guardian_locally, guardian_id, patient_id)
    return await asyncio.to_thread(_linked_guardian_remotely, guardian_id, patient_id)


async def require_authorized_request(request: Request) -> None:
    if not auth_enforced():
        return
    path = request.url.path
    method = request.method.upper()
    if path in {"/api/v1/users", "/api/v1/users/login"} and method == "POST":
        if service_role() != "main":
            raise HTTPException(status_code=404, detail="Not Found")
        return
    if path.startswith("/api/v1/biosignal-test/") or path.startswith("/api/v1/dur/sync"):
        key = os.getenv("ALKONGYAKONG_ADMIN_KEY", "")
        if key and hmac.compare_digest(request.headers.get("x-admin-key", ""), key):
            return
        raise HTTPException(status_code=404, detail="Not Found")
    header = request.headers.get("authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="로그인이 필요해요.")
    claims = verify_token(header[7:].strip())
    segments = [part for part in path.split("/") if part]
    body: dict[str, Any] = {}
    if method in {"POST", "PUT", "PATCH"}:
        try:
            parsed = await request.json()
            body = parsed if isinstance(parsed, dict) else {}
        except (ValueError, UnicodeDecodeError):
            pass

    if claims["kind"] == "service":
        scope = claims.get("scope")
        target = claims.get("target")
        if not isinstance(target, str) or not target:
            raise HTTPException(status_code=403, detail="대상 사용자가 없는 서버 요청이에요.")
        if (
            scope == "medicine_read"
            and method == "GET"
            and len(segments) == 5
            and segments[:3] == ["api", "v1", "users"]
            and segments[4] == "medicines"
            and segments[3] == target
        ) or (
            scope == "dur_consultation"
            and method == "POST"
            and path == "/api/v1/dur/analyze"
            and body.get("analysis_purpose") == "consultation"
            and body.get("user_id") == target
        ) or (
            scope == "patient_read"
            and method == "GET"
            and len(segments) >= 5
            and segments[:3] == ["api", "v1", "users"]
            and segments[3] == target
            and segments[4] in _READABLE_BY_GUARDIAN
        ) or (
            scope == "identity_read" and service_role() == "main"
            and method == "GET" and path == f"/api/v1/auth/identity/{target}"
        ) or (
            scope == "guardian_link_check"
            and service_role() == "main"
            and method == "GET"
            and path == "/api/v1/guardians/internal/authorization"
            and request.query_params.get("guardian_id") == claims["sub"]
            and request.query_params.get("patient_id") == target
        ):
            request.state.auth_identity = {"id": target, "service": True}
            if service_role() == "medication" and scope in {
                "medicine_read", "patient_read", "dur_consultation"
            }:
                identity = await asyncio.to_thread(load_authority_identity, target)
                await asyncio.to_thread(provision_medication_identity, identity)
            return
        raise HTTPException(status_code=403, detail="허용되지 않은 서버 요청이에요.")

    subject = claims["sub"]
    identity = await asyncio.to_thread(load_authority_identity, subject)
    if str(identity.get("role", "")).lower() != claims["role"]:
        raise HTTPException(status_code=401, detail="다시 로그인해 주세요.")
    request.state.auth_identity = identity
    target = None
    if len(segments) >= 4 and segments[:3] == ["api", "v1", "users"]:
        target = segments[3]
    if isinstance(body.get("user_id"), str):
        body_target = body["user_id"]
        if target and body_target != target:
            raise HTTPException(status_code=403, detail="요청한 사용자가 일치하지 않아요.")
        target = body_target
    if request.query_params.get("user_id"):
        query_target = request.query_params["user_id"]
        if target and target != query_target:
            raise HTTPException(status_code=403, detail="요청한 사용자가 일치하지 않아요.")
        target = query_target
    if path.startswith("/api/v1/guardians/"):
        if len(segments) >= 5 and segments[3] == "accounts":
            target = segments[4]
        elif len(segments) >= 5 and segments[3] == "users":
            target = segments[4]
        elif path == "/api/v1/guardians/link-requests":
            target = body.get("guardian_user_id")
        elif len(segments) == 4 and method in {"PATCH", "DELETE"}:
            conn = get_connection()
            try:
                row = conn.execute(
                    "SELECT user_id, guardian_user_id, status FROM guardians WHERE id = ?",
                    (segments[3],),
                ).fetchone()
            finally:
                conn.close()
            if row is None:
                raise HTTPException(status_code=404, detail="연결을 찾지 못했어요.")
            if method == "PATCH":
                target = row["user_id"]
            elif subject in {row["user_id"], row["guardian_user_id"]}:
                return
            else:
                raise HTTPException(status_code=404, detail="연결을 찾지 못했어요.")
    if path == "/api/v1/guardians/internal/authorization":
        raise HTTPException(status_code=403, detail="허용되지 않은 요청이에요.")
    if path.startswith("/api/v1/auth/"):
        raise HTTPException(status_code=403, detail="허용되지 않은 요청이에요.")
    if target == subject:
        await asyncio.to_thread(provision_medication_identity, identity)
        return
    if (
        target
        and (
            (method == "GET" and len(segments) >= 4
             and segments[:3] == ["api", "v1", "users"]
             and (len(segments) == 4 or segments[4] in _READABLE_BY_GUARDIAN))
            or (method == "POST" and path in {
                "/api/v1/prescriptions/ocr", "/api/v1/prescriptions/confirm"
            })
            or (method == "POST" and len(segments) == 7
                and segments[:3] == ["api", "v1", "users"]
                and segments[4] == "prescriptions" and segments[6] == "schedule-days")
        )
        and await _guardian_can_read(subject, target)
    ):
        patient = await asyncio.to_thread(load_authority_identity, target)
        await asyncio.to_thread(provision_medication_identity, patient)
        return
    if target is None and method == "GET" and (
        path in {"/api/v1/drugs/search", "/api/v1/medicines/lookup", "/api/v1/users"}
        or (len(segments) == 4 and segments[:3] == ["api", "v1", "drug-explain"])
    ):
        return
    raise HTTPException(status_code=403, detail="다른 사용자의 정보에 접근할 수 없어요.")
