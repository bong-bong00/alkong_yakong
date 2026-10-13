import pytest
from fastapi import HTTPException

import app.database as database
import init_db
from app.models.schemas import HeartRateCreate, MedicationBatchRequest, MedicationLogCreate
from app.services.biosignal_service import save_heart_rate
from app.services.medication_history_service import get_medication_history
from app.services.medication_service import (
    cancel_medication_taken,
    mark_medication_taken,
    mark_medications_taken,
)
from app.services.prescription_service import _reactivate_duplicate_prescription
from app.services.care_service import get_care_overview


@pytest.fixture
def isolated_db(tmp_path, monkeypatch):
    path = str(tmp_path / "hardening.db")
    monkeypatch.setattr(database, "DB_PATH", path)
    monkeypatch.setattr(init_db, "DB_PATH", path)
    init_db.initialize_database()
    with database.get_connection() as conn:
        conn.execute(
            "INSERT INTO users (id, name, role) VALUES ('patient-a', '환자', 'PATIENT')"
        )
        conn.execute(
            "INSERT INTO users (id, name, role) VALUES ('patient-b', '다른 환자', 'PATIENT')"
        )
        conn.execute(
            "INSERT INTO medicines (medicine_code, product_name, ingredient) "
            "VALUES ('DRUG-1', '검사용 약', '성분')"
        )
        conn.execute(
            "INSERT INTO user_medicines (user_id, medicine_code) "
            "VALUES ('patient-a', 'DRUG-1')"
        )
        medicine_id = conn.execute(
            "SELECT id FROM user_medicines WHERE user_id = 'patient-a'"
        ).fetchone()[0]
        conn.execute(
            "INSERT INTO medication_schedules "
            "(user_id, user_medicine_id, scheduled_date, scheduled_time, status) "
            "VALUES ('patient-a', ?, '2026-10-13', '08:00', 'PENDING')",
            (medicine_id,),
        )
    return path


def _schedule_id():
    with database.get_connection() as conn:
        return conn.execute(
            "SELECT id FROM medication_schedules WHERE user_id = 'patient-a'"
        ).fetchone()[0]


def test_take_cancel_retakes_without_erasing_audit(isolated_db):
    schedule_id = _schedule_id()
    request = MedicationLogCreate(user_id="patient-a", schedule_id=schedule_id)
    first = mark_medication_taken(request)
    assert first["status"] == "TAKEN"
    assert mark_medication_taken(request)["duplicate"] is True
    cancelled = cancel_medication_taken(request)
    assert cancelled["status"] == "CANCELLED"
    assert cancel_medication_taken(request)["duplicate"] is True
    history = get_medication_history("patient-a", "2026-10-13", "2026-10-13")
    assert history["days"][0]["taken"] == 0
    second = mark_medication_taken(request)
    assert second["status"] == "TAKEN"
    assert second["id"] != first["id"]
    with database.get_connection() as conn:
        rows = conn.execute(
            "SELECT status FROM medication_logs WHERE schedule_id = ? ORDER BY id",
            (schedule_id,),
        ).fetchall()
        assert [row["status"] for row in rows] == [
            "TAKEN", "CANCELLED", "TAKEN"
        ]
        assert conn.execute(
            "SELECT status FROM medication_schedules WHERE id = ?", (schedule_id,)
        ).fetchone()["status"] == "TAKEN"


def test_batch_is_atomic_when_one_schedule_is_not_owned(isolated_db):
    schedule_id = _schedule_id()
    with pytest.raises(HTTPException) as error:
        mark_medications_taken(
            MedicationBatchRequest(
                user_id="patient-a", schedule_ids=[schedule_id, 999999]
            )
        )
    assert error.value.status_code == 404
    with database.get_connection() as conn:
        assert conn.execute("SELECT COUNT(*) FROM medication_logs").fetchone()[0] == 0
        assert conn.execute(
            "SELECT status FROM medication_schedules WHERE id = ?", (schedule_id,)
        ).fetchone()["status"] == "PENDING"


def test_heart_request_id_is_idempotent_per_user(isolated_db):
    request = HeartRateCreate(
        user_id="patient-a",
        bpm=72,
        measured_at="2026-10-13T08:10:00",
        client_request_id="measurement-1",
    )
    first = save_heart_rate(request)
    second = save_heart_rate(request)
    assert first["heart_rate_log_id"] == second["heart_rate_log_id"]
    with pytest.raises(HTTPException) as error:
        save_heart_rate(request.model_copy(update={"bpm": 90}))
    assert error.value.status_code == 409
    with database.get_connection() as conn:
        assert conn.execute(
            "SELECT COUNT(*) FROM heart_rate_logs WHERE user_id = 'patient-a'"
        ).fetchone()[0] == 1
    other = save_heart_rate(
        HeartRateCreate(
            user_id="patient-b",
            bpm=90,
            client_request_id="measurement-1",
        )
    )
    assert other["heart_rate_log_id"] != first["heart_rate_log_id"]


def test_duplicate_prescription_keeps_logged_schedule(isolated_db):
    schedule_id = _schedule_id()
    with database.get_connection() as conn:
        conn.execute(
            "INSERT INTO prescriptions (id, user_id) VALUES ('rx-1', 'patient-a')"
        )
        conn.execute(
            """
            INSERT INTO prescription_items (
                prescription_id, medicine_code, ocr_drug_name,
                frequency_per_day, duration_days, administration_times
            ) VALUES ('rx-1', 'DRUG-1', '검사용 약', 1, 1, '["08:00"]')
            """
        )
        item_id = conn.execute(
            "SELECT id FROM prescription_items WHERE prescription_id = 'rx-1'"
        ).fetchone()[0]
        conn.execute(
            "UPDATE user_medicines SET prescription_item_id = ? "
            "WHERE user_id = 'patient-a'",
            (item_id,),
        )
    mark_medication_taken(
        MedicationLogCreate(user_id="patient-a", schedule_id=schedule_id)
    )
    with database.get_connection() as conn:
        _reactivate_duplicate_prescription(
            conn.cursor(), user_id="patient-a", prescription_id="rx-1"
        )
        conn.commit()
        assert conn.execute(
            "SELECT 1 FROM medication_schedules WHERE id = ?", (schedule_id,)
        ).fetchone()
        assert conn.execute(
            "SELECT schedule_id FROM medication_logs WHERE schedule_id = ?",
            (schedule_id,),
        ).fetchone()["schedule_id"] == schedule_id


def test_legacy_guardian_link_requires_reacceptance(isolated_db):
    with database.get_connection() as conn:
        conn.execute(
            """
            INSERT INTO guardians (
                id, user_id, guardian_name, phone, guardian_user_id,
                status, requested_by
            ) VALUES (
                'legacy-link', 'patient-a', '보호자', '010-1234-5678',
                'patient-b', 'ACCEPTED', 'PATIENT'
            )
            """
        )
    init_db.initialize_database()
    with database.get_connection() as conn:
        link = conn.execute(
            "SELECT status, consent_verified_at FROM guardians WHERE id = 'legacy-link'"
        ).fetchone()
        assert link["status"] == "PENDING"
        assert link["consent_verified_at"] is None
    overview = get_care_overview("patient-b")
    assert overview["patients"] == []
    assert overview["pending"][0]["id"] == "legacy-link"


def test_legacy_guardian_requested_link_remains_accepted(isolated_db):
    with database.get_connection() as conn:
        conn.execute(
            """
            INSERT INTO guardians (
                id, user_id, guardian_name, phone, guardian_user_id,
                status, requested_by
            ) VALUES (
                'accepted-link', 'patient-a', '보호자', '010-1234-5678',
                'patient-b', 'ACCEPTED', 'GUARDIAN'
            )
            """
        )
    init_db.initialize_database()
    init_db.initialize_database()
    with database.get_connection() as conn:
        link = conn.execute(
            "SELECT status, consent_verified_at FROM guardians WHERE id = 'accepted-link'"
        ).fetchone()
        assert link["status"] == "ACCEPTED"
        assert link["consent_verified_at"]
    assert get_care_overview("patient-b")["patients"][0]["patient_id"] == "patient-a"
