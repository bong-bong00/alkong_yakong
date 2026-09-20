import sqlite3

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import app.database as database
from app.routes import users
from app.services.today_medication_service import _course_fields
from init_db import TABLE_DEFINITIONS


@pytest.fixture
def client(tmp_path, monkeypatch):
    db_path = tmp_path / "users.db"
    conn = sqlite3.connect(db_path)
    for definition in TABLE_DEFINITIONS.values():
        conn.execute(definition)
    conn.commit()
    conn.close()
    monkeypatch.setattr(database, "DB_PATH", str(db_path))
    api = FastAPI()
    api.include_router(users.router)
    return TestClient(api)


def _signup(client, **overrides):
    body = {
        "name": "김복자",
        "phone": "010-1234-5678",
        "password": "abc123",
        "role": "patient",
        "birth_date": "1958-04-10",
        "gender": "F",
        "height_cm": 158,
        "allergies": ["페니실린"],
        "diseases": ["고혈압", "당뇨"],
        "past_history": False,
    }
    body.update(overrides)
    return client.post("/api/v1/users", json=body)


def test_signup_saves_profile_without_exposing_password(client):
    response = _signup(client)
    assert response.status_code == 200
    user = response.json()
    assert "password" not in user and "password_hash" not in user
    assert user["allergies"] == ["페니실린"]
    assert user["diseases"] == ["고혈압", "당뇨"]
    assert user["height_cm"] == 158
    assert user["past_history"] is False
    assert user["family_history"] is None

    fetched = client.get(f"/api/v1/users/{user['id']}").json()
    assert fetched["name"] == "김복자"
    assert "password_hash" not in fetched


def test_login_matches_phone_without_hyphens(client):
    user = _signup(client).json()

    ok = client.post(
        "/api/v1/users/login", json={"phone": "01012345678", "password": "abc123"}
    )
    assert ok.status_code == 200
    assert ok.json()["id"] == user["id"]

    wrong = client.post(
        "/api/v1/users/login", json={"phone": "01012345678", "password": "nope00"}
    )
    assert wrong.status_code == 401


def test_same_phone_cannot_sign_up_twice(client):
    assert _signup(client).status_code == 200
    assert _signup(client, phone="01012345678").status_code == 409


def test_update_changes_only_sent_fields(client):
    user = _signup(client).json()

    response = client.patch(
        f"/api/v1/users/{user['id']}",
        json={"name": "김순자", "allergies": [], "pregnancy_status": "임신 중"},
    )
    assert response.status_code == 200
    updated = response.json()
    assert updated["name"] == "김순자"
    assert updated["allergies"] == []
    assert updated["is_pregnant"] is True
    # 보내지 않은 칸은 그대로다.
    assert updated["diseases"] == ["고혈압", "당뇨"]
    assert updated["birth_date"] == "1958-04-10"

    assert client.get(f"/api/v1/users/{user['id']}").json()["name"] == "김순자"
    blank = client.patch(f"/api/v1/users/{user['id']}", json={"name": "  "})
    assert blank.status_code == 400


def test_delete_removes_account(client):
    user = _signup(client).json()
    assert client.delete(f"/api/v1/users/{user['id']}").status_code == 204
    assert client.get(f"/api/v1/users/{user['id']}").status_code == 404
    login = client.post(
        "/api/v1/users/login", json={"phone": "01012345678", "password": "abc123"}
    )
    assert login.status_code == 401


def test_medication_history_counts_slots_per_day(client):
    user = _signup(client).json()
    conn = database.get_connection()
    conn.execute(
        "INSERT INTO medicines (medicine_code, product_name, ingredient) "
        "VALUES ('A1', '약A', '성분A'), ('B1', '약B', '성분B')"
    )
    conn.execute(
        "INSERT INTO user_medicines (id, user_id, medicine_code) "
        "VALUES (1, ?, 'A1'), (2, ?, 'B1')",
        (user["id"], user["id"]),
    )
    rows = [
        (1, "2026-09-01", "08:00", "MORNING", "TAKEN"),
        (2, "2026-09-01", "08:00", "MORNING", "TAKEN"),
        (1, "2026-09-01", "20:00", "EVENING", "TAKEN"),
        (1, "2026-09-02", "08:00", "MORNING", "TAKEN"),
        (2, "2026-09-02", "08:00", "MORNING", "MISSED"),
        (1, "2026-09-02", "13:00", "LUNCH", "PENDING"),
    ]
    conn.executemany(
        "INSERT INTO medication_schedules "
        "(user_id, user_medicine_id, scheduled_date, scheduled_time, time_slot, status) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        [(user["id"], *row) for row in rows],
    )
    conn.commit()
    conn.close()

    response = client.get(
        f"/api/v1/users/{user['id']}/medication-history",
        params={"start": "2026-09-01", "end": "2026-09-03"},
    )
    assert response.status_code == 200
    days = response.json()["days"]
    assert days == [
        {"date": "2026-09-01", "total": 2, "taken": 2, "missed_slots": []},
        # 아침 약 둘 중 하나를 빠뜨리면 아침 전체를 못 드신 것으로 본다.
        {"date": "2026-09-02", "total": 2, "taken": 0, "missed_slots": ["아침", "점심"]},
    ]


def test_course_fields_count_days_until_end():
    course = {"start_date": "2026-09-01", "end_date": "2026-09-21"}
    assert _course_fields(course, "2026-09-14") == {
        "days_left": 7,
        "course_started_on": "2026-09-01",
        "course_total_days": 21,
    }
    assert _course_fields(None, "2026-09-14")["days_left"] is None


def test_user_list_is_closed_when_no_admin_key_is_set(client):
    # 열쇠를 정하지 않은 서버에서는 회원 목록 길이 아예 없다.
    assert client.get("/api/v1/users").status_code == 404


def test_user_list_needs_the_admin_key(client, monkeypatch):
    monkeypatch.setenv("ALKONGYAKONG_ADMIN_KEY", "secret-key")
    _signup(client)

    assert client.get("/api/v1/users").status_code == 403
    wrong = client.get("/api/v1/users", headers={"X-Admin-Key": "nope"})
    assert wrong.status_code == 403

    allowed = client.get("/api/v1/users", headers={"X-Admin-Key": "secret-key"})
    assert allowed.status_code == 200
    listed = allowed.json()
    assert [user["name"] for user in listed] == ["김복자"]
    assert "password_hash" not in listed[0]
