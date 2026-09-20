from datetime import date
import sqlite3

from app.services import dashboard_service
from app.services.dashboard_service import get_medication_calendar
from init_db import TABLE_DEFINITIONS


def test_days_without_schedules_are_not_marked_missed(tmp_path, monkeypatch):
    db_path = tmp_path / "calendar.sqlite3"

    def _open():
        opened = sqlite3.connect(db_path)
        opened.row_factory = sqlite3.Row
        return opened

    conn = _open()
    conn.execute(TABLE_DEFINITIONS["users"])
    conn.execute(TABLE_DEFINITIONS["medicines"])
    conn.execute(TABLE_DEFINITIONS["user_medicines"])
    conn.execute(TABLE_DEFINITIONS["medication_schedules"])
    conn.execute(
        "INSERT INTO users (id, name, role) VALUES ('cal-user', '환자', 'PATIENT')"
    )
    conn.commit()
    conn.close()
    monkeypatch.setattr(dashboard_service, "get_connection", _open)

    today = date.today()
    result = get_medication_calendar("cal-user", today.year, today.month)
    assert result["has_schedules"] is False
    assert all(day["mark"] != "missed" for day in result["days"])
    assert result["missed"] == []
    today_marks = [day["mark"] for day in result["days"] if day["day"] == today.day]
    assert today_marks == ["today"]


def test_each_day_carries_its_slot_results(tmp_path, monkeypatch):
    """날짜를 누르면 그날 결과를 보여줘야 한다. 달력이 시간대까지 내려준다."""
    db_path = tmp_path / "calendar-slots.sqlite3"

    def _open():
        opened = sqlite3.connect(db_path)
        opened.row_factory = sqlite3.Row
        return opened

    conn = _open()
    for table in ("users", "medicines", "user_medicines", "medication_schedules"):
        conn.execute(TABLE_DEFINITIONS[table])
    conn.execute(
        "INSERT INTO users (id, name, role) VALUES ('slot-user', '환자', 'PATIENT')"
    )
    conn.execute(
        "INSERT INTO user_medicines (id, user_id, medicine_code, is_active)"
        " VALUES (1, 'slot-user', 'M1', 1)"
    )
    yesterday = date.today().replace(day=1)
    conn.execute(
        "INSERT INTO medication_schedules"
        " (user_id, user_medicine_id, scheduled_date, scheduled_time, time_slot, status)"
        " VALUES ('slot-user', 1, ?, '08:00', 'MORNING', 'TAKEN')",
        (yesterday.isoformat(),),
    )
    conn.execute(
        "INSERT INTO medication_schedules"
        " (user_id, user_medicine_id, scheduled_date, scheduled_time, time_slot, status)"
        " VALUES ('slot-user', 1, ?, '18:00', 'EVENING', 'PENDING')",
        (yesterday.isoformat(),),
    )
    conn.commit()
    conn.close()
    monkeypatch.setattr(dashboard_service, "get_connection", _open)

    result = get_medication_calendar("slot-user", yesterday.year, yesterday.month)
    first = [day for day in result["days"] if day["day"] == yesterday.day][0]
    assert first["slots"] == [
        {"slot": "아침", "taken": True},
        {"slot": "저녁", "taken": False},
    ]
    # 일정이 없던 날은 빈 목록이다. 없는 기록을 지어내지 않는다.
    empty = [day for day in result["days"] if day["day"] != yesterday.day]
    assert all(day["slots"] == [] for day in empty)
