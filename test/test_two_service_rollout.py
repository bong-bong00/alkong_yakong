from contextvars import ContextVar
import json
import sqlite3
import sys
from urllib.parse import urlsplit

from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
import pytest
import requests

import app.database as database
from app.core import auth
from app.core.kst import today_kst
from app.routes import auth as auth_routes, biosignal, dashboard, guardians, internal, medication_logs, notifications, users
from app.services import medication_feature_dur_client as remote
from init_db import TABLE_DEFINITIONS


@pytest.fixture
def services(tmp_path, monkeypatch):
    """Two real APIs, isolated DBs and signed internal HTTP calls, no network."""
    role = ContextVar("test_service_role", default="main")
    paths = {name: tmp_path / f"{name}.db" for name in ("main", "medication")}
    for path in paths.values():
        with sqlite3.connect(path) as conn:
            for definition in TABLE_DEFINITIONS.values():
                conn.execute(definition)

    original_connection = database.get_connection
    original_role = auth.service_role
    def connection():
        conn = sqlite3.connect(paths[role.get()], timeout=10)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys=ON")
        return conn
    for module in list(sys.modules.values()):
        if not module or not getattr(module, "__name__", "").startswith("app."):
            continue
        if getattr(module, "get_connection", None) is original_connection:
            monkeypatch.setattr(module, "get_connection", connection)
        if getattr(module, "service_role", None) is original_role:
            monkeypatch.setattr(module, "service_role", role.get)
    monkeypatch.setenv("AUTH_ENFORCED", "true")
    monkeypatch.setenv("ALKONGYAKONG_AUTH_SECRET", "test-two-service-shared-key-not-for-production")
    monkeypatch.setenv("AUTH_AUTHORITY_BASE_URL", "https://main.test")
    monkeypatch.setattr(remote, "MEDICATION_FEATURE_BASE_URL", "https://medication.test")
    import app.core.config as config
    monkeypatch.setattr(config, "MEDICATION_FEATURE_BASE_URL", "https://medication.test")

    class RoleMiddleware:
        def __init__(self, app, current_role):
            self.app, self.current_role = app, current_role
        async def __call__(self, scope, receive, send):
            token = role.set(self.current_role)
            try:
                await self.app(scope, receive, send)
            finally:
                role.reset(token)

    clients = {}
    for name in paths:
        api = FastAPI(dependencies=[Depends(auth.require_authorized_request)])
        api.add_middleware(RoleMiddleware, current_role=name)
        for router in (auth_routes.router, users.router, guardians.router,
                       dashboard.router, medication_logs.router, biosignal.router,
                       notifications.router, internal.router):
            api.include_router(router)
        clients[name] = TestClient(api)

    calls = []
    def internal_get(url, **kwargs):
        split = urlsplit(url)
        name = "main" if split.hostname == "main.test" else "medication"
        assert split.hostname in {"main.test", "medication.test"}, "Unexpected external network call"
        credential = kwargs["headers"]["Authorization"][7:]
        claims = auth.verify_token(credential)
        assert claims["kind"] == "service"
        calls.append((name, claims["scope"], claims["target"]))
        response = clients[name].get(split.path, params=kwargs.get("params"), headers=kwargs["headers"])
        wrapped = requests.Response()
        wrapped.status_code = response.status_code
        wrapped._content = response.content
        wrapped.url = url
        return wrapped
    monkeypatch.setattr(requests, "get", internal_get)
    def internal_delete(url, **kwargs):
        split = urlsplit(url)
        assert split.hostname == "medication.test"
        claims = auth.verify_token(kwargs["headers"]["Authorization"][7:])
        assert claims["scope"] == "account_purge"
        response = clients["medication"].delete(split.path, headers=kwargs["headers"])
        wrapped = requests.Response()
        wrapped.status_code = response.status_code
        wrapped._content = response.content
        wrapped.url = url
        return wrapped
    monkeypatch.setattr(requests, "delete", internal_delete)
    yield clients, paths, calls
    for client in clients.values():
        client.close()


def signup(client, phone, role):
    response = client.post("/api/v1/users", json={
        "name": "연동 사용자", "phone": phone, "password": "test123", "role": role,
    })
    assert response.status_code == 200, response.text
    data = response.json()
    return data, {"Authorization": f"Bearer {data['access_token']}"}


def test_two_db_take_cancel_guardian_read_and_revoke(services):
    clients, paths, calls = services
    main, medication = clients["main"], clients["medication"]
    patient, patient_header = signup(main, "01011112222", "patient")
    guardian, guardian_header = signup(main, "01033334444", "guardian")
    today_path = f"/api/v1/users/{patient['id']}/today-medicines"
    assert medication.get(today_path).status_code == 401
    assert medication.get(today_path, headers=patient_header).status_code == 200
    day = today_kst().isoformat()
    with sqlite3.connect(paths["medication"]) as conn:
        conn.execute("INSERT INTO medicines (medicine_code, product_name, ingredient) VALUES ('TEST-MED', '검증약정', '검증성분')")
        conn.execute("""INSERT INTO user_medicines (id, user_id, medicine_code, frequency_per_day,
                     administration_times, start_date, end_date, is_active)
                     VALUES (1, ?, 'TEST-MED', 1, '["08:00"]', ?, ?, 1)""", (patient["id"], day, day))
        conn.execute("""INSERT INTO medication_schedules (id, user_id, user_medicine_id,
                         scheduled_date, scheduled_time, time_slot, status)
                         VALUES (1, ?, 1, ?, '08:00', 'MORNING', 'PENDING')""", (patient["id"], day))
    link = main.post("/api/v1/guardians/link-requests", headers=guardian_header, json={
        "guardian_user_id": guardian["id"], "patient_phone": "01011112222",
    }).json()["id"]
    assert medication.get(today_path, headers=guardian_header).status_code == 403
    assert main.patch(f"/api/v1/guardians/{link}", headers=patient_header,
                      json={"status": "ACCEPTED"}).status_code == 200
    assert medication.get(today_path, headers=guardian_header).status_code == 200
    payload = {"user_id": patient["id"], "schedule_ids": [1]}
    assert medication.post("/api/v1/medication-logs/batch", headers=guardian_header, json=payload).status_code == 403
    assert medication.post("/api/v1/medication-logs/batch", headers=patient_header, json=payload).status_code == 200
    overview_path = f"/api/v1/guardians/accounts/{guardian['id']}/patients"
    response = main.get(overview_path, headers=guardian_header)
    assert response.status_code == 200, response.text
    assert response.json()["patients"][0]["taken_count"] == 1
    assert response.json()["patients"][0]["total_count"] == 1
    assert medication.post("/api/v1/medication-logs/batch/cancel", headers=patient_header, json=payload).status_code == 200
    assert main.get(overview_path, headers=guardian_header).json()["patients"][0]["taken_count"] == 0
    heart = {"user_id": patient["id"], "bpm": 72, "client_request_id": "measurement-1"}
    first = main.post("/api/v1/biosignal/heart-rate", headers=patient_header, json=heart)
    second = main.post("/api/v1/biosignal/heart-rate", headers=patient_header, json=heart)
    assert first.json()["heart_rate_log_id"] == second.json()["heart_rate_log_id"]
    assert main.get(overview_path, headers=guardian_header).json()["patients"][0]["heart_rate"] == 72
    assert main.post(f"/api/v1/users/{patient['id']}/prescription-help-requests", headers=patient_header).status_code == 200
    assert len(main.get(f"/api/v1/users/{guardian['id']}/notifications", headers=guardian_header).json()) == 1
    assert main.delete(f"/api/v1/guardians/{link}", headers=guardian_header).status_code == 204
    assert medication.get(today_path, headers=guardian_header).status_code == 403
    assert main.get(overview_path, headers=guardian_header).json()["patients"] == []
    assert main.get(f"/api/v1/users/{guardian['id']}/notifications", headers=guardian_header).json() == []
    assert {scope for _, scope, _ in calls} >= {"identity_read", "guardian_link_check", "patient_read"}
    with sqlite3.connect(paths["medication"]) as conn:
        assert conn.execute("SELECT status FROM medication_logs ORDER BY id").fetchall() == [("TAKEN",), ("CANCELLED",)]
    assert main.delete(f"/api/v1/users/{patient['id']}", headers=patient_header).status_code == 204
    for path in paths.values():
        with sqlite3.connect(path) as conn:
            assert conn.execute("SELECT 1 FROM users WHERE id=?", (patient["id"],)).fetchone() is None
    assert medication.get(today_path, headers=patient_header).status_code == 401
