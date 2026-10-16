from datetime import datetime, timezone, timedelta
import pytest
import app.services.care_service as care

KST = timezone(timedelta(hours=9))

@pytest.mark.parametrize("dose,expected", [
    ({"taken": True}, "recorded"),
    ({"taken": False, "scheduled_times": ["18:00"]}, "scheduled"),
    ({"taken": False, "scheduled_times": ["08:00"]}, "overdue"),
    ({"taken": False, "scheduled_times": ["12:00"]}, "overdue"),
    ({"taken": False, "scheduled_times": ["08:00", "18:00"]}, "scheduled"),
    ({"taken": False}, "time_unknown"),
    ({"taken": False, "scheduled_times": []}, "time_unknown"),
    ({"taken": False, "scheduled_times": ["morning"]}, "time_unknown"),
    ({"taken": False, "scheduled_times": ["25:00"]}, "time_unknown"),
    ({"taken": False, "scheduled_times": ["08:00", None]}, "time_unknown"),
])
def test_status_only_uses_known_schedule_times(dose, expected):
    assert care._dose_record_status(dose, datetime(2026, 10, 16, 12, tzinfo=KST)) == expected

def test_guardian_summary_distinguishes_next_and_overdue(monkeypatch):
    class FixedDatetime(datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2026, 10, 16, 12, tzinfo=KST)
    class Connection:
        def close(self):
            pass
    monkeypatch.setattr(care, "datetime", FixedDatetime)
    monkeypatch.setattr(care, "auth_enforced", lambda: False)
    monkeypatch.setattr(care, "get_connection", Connection)
    monkeypatch.setattr(care, "latest_heart_reading", lambda *args: None)
    monkeypatch.setattr(care, "_activities", lambda *args, **kwargs: [])
    monkeypatch.setattr(care, "get_medication_history", lambda *args: {"days": []})
    doses = [{"slot": "morning", "taken": True, "scheduled_times": ["08:00"]},
             {"slot": "dinner", "taken": False, "scheduled_times": ["18:00"]}]
    monkeypatch.setattr(care, "get_today_medicines", lambda uid: {"doses": doses})
    row = {"id": "link", "user_id": "p", "patient_name": "test", "patient_phone": "000",
           "patient_relation": "", "patient_birth_date": None}
    result = care._patient_summary(row)
    assert result["dose_status"] == "scheduled"
    assert result["next_dose_label"] == "저녁 약"
    assert result["overdue_dose_label"] is None
    doses[0]["taken"] = False
    result = care._patient_summary(row)
    assert result["dose_status"] == "overdue"
    assert result["overdue_dose_label"] == "아침 약"
    assert result["slots"][1]["record_status"] == "scheduled"
