import sqlite3

import pytest
from fastapi import HTTPException

from app.services import notification_service
from init_db import TABLE_DEFINITIONS


def _conn():
    """어르신 한 분과 보호자 한 분이 들어 있는 메모리 DB."""
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    # notifications 는 사건·일정·기록에 외래키를 건다. 켜 둔 FK 검사를
    # 통과하려면 그 표들도 함께 세워야 한다.
    for table in (
        "users",
        "guardians",
        "medicines",
        "user_medicines",
        "medication_schedules",
        "medication_logs",
        "heart_rate_logs",
        "abnormal_events",
        "notifications",
    ):
        conn.execute(TABLE_DEFINITIONS[table])
    conn.execute(
        "INSERT INTO users (id, name, role) VALUES ('u1', '김복자', 'patient')"
    )
    return conn


class _KeepOpen:
    """close()를 삼키는 껍데기.

    서비스는 일을 마치면 연결을 닫는다. 시험은 그 뒤에 표를 들여다봐야
    하므로 닫히지 않게 감싼다.
    """

    def __init__(self, conn):
        self._conn = conn

    def __getattr__(self, name):
        return getattr(self._conn, name)

    def close(self):
        pass


def _patch(monkeypatch, conn):
    """서비스가 이 연결만 쓰게 한다."""
    monkeypatch.setattr(
        notification_service,
        "get_connection",
        lambda: _KeepOpen(conn),
    )


def test_help_request_reaches_every_linked_guardian(monkeypatch):
    conn = _conn()
    conn.execute(
        """
        INSERT INTO guardians (id, user_id, guardian_name, relationship, status)
        VALUES ('g1', 'u1', '김지안', '딸', 'ACCEPTED')
        """
    )
    conn.execute(
        """
        INSERT INTO guardians (id, user_id, guardian_name, relationship, status)
        VALUES ('g2', 'u1', '김민수', '아들', 'PENDING')
        """
    )
    _patch(monkeypatch, conn)

    result = notification_service.request_prescription_help("u1")

    assert result["sent"] is True
    # 아직 수락하지 않은 가족에게는 보내지 않는다. 받을 수 없는 사람이다.
    assert result["guardians"] == ["딸 김지안"]

    rows = conn.execute(
        "SELECT user_id, guardian_id, notification_type, message, status"
        " FROM notifications"
    ).fetchall()
    assert len(rows) == 1
    assert rows[0]["user_id"] == "u1"
    assert rows[0]["guardian_id"] == "g1"
    assert rows[0]["notification_type"] == "PRESCRIPTION_HELP_REQUEST"
    # 누가 부탁했는지 알림 글에 적는다. 보호자는 여러 분을 돌볼 수 있다.
    assert "김복자" in rows[0]["message"]
    assert rows[0]["status"] == "PENDING"


def test_help_request_without_guardian_sends_nothing(monkeypatch):
    conn = _conn()
    _patch(monkeypatch, conn)

    result = notification_service.request_prescription_help("u1")

    # 받을 사람이 없으면 보냈다고 하지 않는다. 어르신이 하염없이 기다린다.
    assert result["sent"] is False
    assert result["reason"] == "NO_GUARDIAN"
    assert conn.execute("SELECT COUNT(*) FROM notifications").fetchone()[0] == 0


def test_help_request_for_unknown_user_is_404(monkeypatch):
    conn = _conn()
    _patch(monkeypatch, conn)

    with pytest.raises(HTTPException) as error:
        notification_service.request_prescription_help("nobody")
    assert error.value.status_code == 404
