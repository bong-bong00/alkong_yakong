import sqlite3
import time

import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

import app.database as database
from app.core import auth
from app.routes import auth as auth_routes, guardians, users, medication_logs
from init_db import TABLE_DEFINITIONS


@pytest.fixture
def client(tmp_path, monkeypatch):
    path = tmp_path / "auth.db"
    conn = sqlite3.connect(path)
    for definition in TABLE_DEFINITIONS.values():
        conn.execute(definition)
    conn.commit()
    conn.close()
    monkeypatch.setattr(database, "DB_PATH", str(path))
    monkeypatch.setenv("AUTH_ENFORCED", "true")
    monkeypatch.setenv("SERVICE_ROLE", "main")
    monkeypatch.setenv("ALKONGYAKONG_AUTH_SECRET", "unit-test-key-is-not-a-production-secret")
    monkeypatch.setenv("ALKONGYAKONG_DB_PATH", str(path))
    monkeypatch.setenv("MEDICATION_FEATURE_BASE_URL", "https://medication.invalid")
    monkeypatch.setenv("AUTH_AUTHORITY_BASE_URL", "https://main.invalid")
    api = FastAPI(dependencies=[Depends(auth.require_authorized_request)])
    for router in (users.router, guardians.router, medication_logs.router, auth_routes.router):
        api.include_router(router)

    @api.get("/api/v1/medicines/lookup")
    def lookup():
        return {"items": []}

    @api.post("/api/v1/prescriptions/ocr")
    @api.post("/api/v1/prescriptions/confirm")
    @api.post("/api/v1/biosignal/heart-rate")
    @api.post("/api/v1/drug-explain/chat")
    @api.post("/api/v1/dur/analyze")
    def write(body: dict):
        return body

    @api.get("/api/v1/users/{user_id}/today-medicines")
    def today(user_id: str):
        return {"user_id": user_id, "doses": []}

    @api.get("/api/v1/drug-explain/cache-context")
    def cache_context(user_id: str):
        return {"verified": True, "fingerprint": user_id}

    return TestClient(api)


def test_guardian_chat_and_cache_are_bound_to_current_accepted_patient(client):
    patient = signup(client)
    guardian = signup(client, '01033334444', 'guardian')
    other = signup(client, '01055556666')
    body = {'user_id': patient['id'], 'message': '주의사항'}
    cache = '/api/v1/drug-explain/cache-context?user_id=' + patient['id']
    assert client.post('/api/v1/drug-explain/chat', headers=header(guardian), json=body).status_code == 403
    assert client.get(cache, headers=header(guardian)).status_code == 403
    link = client.post('/api/v1/guardians/link-requests', headers=header(guardian), json={
        'guardian_user_id': guardian['id'], 'patient_phone': '01011112222'}).json()['id']
    assert client.patch('/api/v1/guardians/' + link, headers=header(patient), json={'status': 'ACCEPTED'}).status_code == 200
    assert client.post('/api/v1/drug-explain/chat', headers=header(guardian), json=body).status_code == 200
    assert client.get(cache, headers=header(guardian)).status_code == 200
    assert client.post('/api/v1/drug-explain/chat', headers=header(guardian), json={**body, 'user_id': other['id']}).status_code == 403
    assert client.delete('/api/v1/guardians/' + link, headers=header(patient)).status_code == 204
    assert client.post('/api/v1/drug-explain/chat', headers=header(guardian), json=body).status_code == 403
    assert client.get(cache, headers=header(guardian)).status_code == 403


def signup(client, phone="01011112222", role="patient"):
    response = client.post("/api/v1/users", json={
        "name": "테스트 사용자", "phone": phone, "password": "test123", "role": role,
    })
    assert response.status_code == 200, response.text
    return response.json()


def header(account):
    return {"Authorization": f"Bearer {account['access_token']}"}


def test_login_issues_credential_and_rejects_unauthenticated_or_other_user(client):
    account = signup(client)
    other = signup(client, "01033334444")
    assert client.get(f"/api/v1/users/{account['id']}").status_code == 401
    assert client.get(f"/api/v1/users/{account['id']}", headers=header(account)).status_code == 200
    assert client.get(f"/api/v1/users/{other['id']}", headers=header(account)).status_code == 403
    assert client.patch(f"/api/v1/users/{other['id']}", json={"name": "changed"},
                        headers=header(account)).status_code == 403
    logged_in = client.post("/api/v1/users/login", json={"phone": "01011112222", "password": "test123"})
    assert logged_in.status_code == 200
    assert auth.verify_token(logged_in.json()["access_token"])["sub"] == account["id"]
    assert "password_hash" not in logged_in.json()
    assert client.get("/api/v1/medicines/lookup", headers=header(account)).status_code == 200


@pytest.mark.parametrize("path", [
    "/api/v1/prescriptions/ocr", "/api/v1/prescriptions/confirm",
    "/api/v1/biosignal/heart-rate", "/api/v1/drug-explain/chat", "/api/v1/dur/analyze",
    "/api/v1/medication-logs", "/api/v1/medication-logs/batch/cancel",
])
def test_body_id_cannot_impersonate_other_patient(client, path):
    account = signup(client)
    other = signup(client, "01033334444")
    response = client.post(path, headers=header(account), json={
        "user_id": other["id"], "schedule_id": 1, "schedule_ids": [1],
    })
    assert response.status_code == 403


def test_guardian_acceptance_is_patient_only_and_revocation_is_immediate(client):
    patient = signup(client)
    guardian = signup(client, "01033334444", "guardian")
    request = client.post("/api/v1/guardians/link-requests", headers=header(guardian), json={
        "guardian_user_id": guardian["id"], "patient_phone": "01011112222",
    })
    link_id = request.json()["id"]
    path = f"/api/v1/users/{patient['id']}/today-medicines"
    assert client.get(path, headers=header(guardian)).status_code == 403
    assert client.patch(f"/api/v1/guardians/{link_id}", headers=header(guardian),
                        json={"status": "ACCEPTED"}).status_code == 403
    assert client.patch(f"/api/v1/guardians/{link_id}", headers=header(patient),
                        json={"status": "ACCEPTED"}).status_code == 200
    assert client.get(path, headers=header(guardian)).status_code == 200
    assert client.get(f"/api/v1/users/{patient['id']}", headers=header(guardian)).status_code == 200
    assert client.patch(f"/api/v1/users/{patient['id']}", headers=header(guardian),
                        json={"name": "changed"}).status_code == 403
    assert client.post("/api/v1/prescriptions/ocr", headers=header(guardian),
                       json={"user_id": patient["id"]}).status_code == 200
    assert client.delete(f"/api/v1/guardians/{link_id}", headers=header(guardian)).status_code == 204
    assert client.get(path, headers=header(guardian)).status_code == 403


def test_deleted_identity_cannot_use_old_token(client, monkeypatch):
    from unittest.mock import Mock
    import requests
    import app.core.config as config
    monkeypatch.setattr(config, 'MEDICATION_FEATURE_BASE_URL', 'https://medication.test')
    monkeypatch.setattr(requests, 'delete', Mock(return_value=Mock(status_code=204)))
    account = signup(client)
    assert client.delete(f"/api/v1/users/{account['id']}", headers=header(account)).status_code == 204
    assert client.get("/api/v1/medicines/lookup", headers=header(account)).status_code == 401


def test_invalid_expired_and_wrong_kind_tokens_are_rejected(client, monkeypatch):
    account = signup(client)
    token = account["access_token"]
    assert client.get("/api/v1/medicines/lookup", headers={"Authorization": f"Bearer {token}x"}).status_code == 401
    future = time.time() + 8 * 24 * 3600
    monkeypatch.setattr(auth.time, "time", lambda: future)
    assert client.get("/api/v1/medicines/lookup", headers=header(account)).status_code == 401


def test_service_credential_is_bound_to_user_and_endpoint(client):
    account = signup(client)
    token, _ = auth.issue_token("main", role="service", kind="service",
                               target=account["id"], scope="dur_consultation")
    headers = {"Authorization": f"Bearer {token}"}
    assert client.post("/api/v1/dur/analyze", headers=headers, json={
        "user_id": account["id"], "analysis_purpose": "consultation",
    }).status_code == 200
    assert client.post("/api/v1/dur/analyze", headers=headers, json={
        "user_id": account["id"], "analysis_purpose": "medication",
    }).status_code == 403
    assert client.get(f"/api/v1/users/{account['id']}", headers=headers).status_code == 403
    assert client.post("/api/v1/dur/analyze", headers=headers, json={
        "user_id": "other", "analysis_purpose": "consultation",
    }).status_code == 403


def test_medication_service_checks_authority_before_provisioning(client, monkeypatch):
    account = signup(client)
    monkeypatch.setenv("SERVICE_ROLE", "medication")
    calls = []
    class Response:
        status_code = 200
        def raise_for_status(self):
            pass
        def json(self):
            return {"id": account["id"], "name": "사용자", "role": "patient"}
    def get(url, **kwargs):
        claims = auth.verify_token(kwargs["headers"]["Authorization"][7:])
        calls.append(claims)
        assert claims["scope"] == "identity_read"
        return Response()
    monkeypatch.setattr(auth.requests, "get", get)
    assert client.get(f"/api/v1/users/{account['id']}/today-medicines", headers=header(account)).status_code == 200
    assert len(calls) == 1
    assert client.post("/api/v1/users/login", json={"phone": "x", "password": "x"}).status_code == 404


def test_render_configuration_fails_closed(client, monkeypatch):
    auth.validate_auth_configuration()
    monkeypatch.setenv("RENDER", "true")
    monkeypatch.setenv("AUTH_ENFORCED", "false")
    with pytest.raises(RuntimeError, match="AUTH_ENFORCED"):
        auth.validate_auth_configuration()
    monkeypatch.setenv("AUTH_ENFORCED", "true")
    monkeypatch.delenv("ALKONGYAKONG_AUTH_SECRET")
    with pytest.raises(RuntimeError, match="AUTH_SECRET"):
        auth.validate_auth_configuration()
