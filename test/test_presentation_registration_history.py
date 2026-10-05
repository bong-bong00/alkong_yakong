import sqlite3
from datetime import datetime, timezone, timedelta

from init_db import TABLE_DEFINITIONS
from app.models.schemas import PrescriptionConfirmRequest, PrescriptionConfirmItem
from app.services.prescription_service import confirm_prescription, get_user_prescriptions
from app.services.medication_history_service import get_medication_history
from app.services.biosignal_service import get_heart_summary
from scripts.seed_presentation_history import seed_hearts, seed_medications


def prepare(tmp_path, monkeypatch):
    path = tmp_path / "history.db"
    with sqlite3.connect(path) as conn:
        for definition in TABLE_DEFINITIONS.values():
            conn.execute(definition)
        conn.execute("INSERT INTO users(id,name,role) VALUES('demo','시연 전용','PATIENT')")
        conn.execute("INSERT INTO medicines(medicine_code,product_name,ingredient) VALUES('TEST-HISTORY','기록테스트약','시험성분')")
    monkeypatch.setattr("app.database.DB_PATH", str(path))
    return path


def test_confirmed_prescription_is_returned_in_profile_history(tmp_path, monkeypatch):
    prepare(tmp_path, monkeypatch)
    result = confirm_prescription(PrescriptionConfirmRequest(
        user_id="demo", prescribed_date="2026-10-05",
        items=[PrescriptionConfirmItem(
            medicine_code="TEST-HISTORY", drug_name="기록테스트약", duration_days=7,
            frequency_per_day=1, administration_times=["08:00"], match_status="MATCHED",
        )],
    ))
    history = get_user_prescriptions("demo")
    assert history[0]["id"] == result["prescription_id"]
    assert history[0]["items"][0]["product_name"] == "기록테스트약"
    assert history[0]["items"][0]["duration_days"] == 7


def test_demo_records_feed_real_graph_and_calendar_queries(tmp_path, monkeypatch):
    path = prepare(tmp_path, monkeypatch)
    with sqlite3.connect(path) as conn:
        seed_hearts(conn, "demo")
        seed_medications(conn, "demo")
    history = get_medication_history("demo", "2026-09-21", "2026-09-27")
    assert len(history["days"]) == 7
    assert sum(day["taken"] for day in history["days"]) == 19
    summary = get_heart_summary("demo", datetime(2026, 10, 6, 10, tzinfo=timezone(timedelta(hours=9))),
                                include_readings=True, utc_offset_minutes=540)
    assert len(summary["readings"]) == 10
    assert all(row["measurement_context"] in ("before_medication", "after_medication")
               for row in summary["readings"])
