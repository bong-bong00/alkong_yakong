import sqlite3

import pytest

import init_db
from scripts.hardening_database import prepare


@pytest.fixture
def legacy_db(tmp_path):
    path = tmp_path / "legacy.db"
    with sqlite3.connect(path) as conn:
        for definition in init_db.TABLE_DEFINITIONS.values():
            conn.execute(definition)
        conn.execute("INSERT INTO users (id, name, role) VALUES ('existing-user', '보존 대상', 'PATIENT')")
        conn.execute("INSERT INTO medicines (medicine_code, product_name, ingredient) VALUES ('OCR-legacy', '과거 기록', '성분')")
        conn.execute("INSERT INTO prescriptions (id, user_id) VALUES ('original-rx', 'existing-user')")
        conn.execute("INSERT INTO user_medicines (id, user_id, medicine_code, is_active) VALUES (1, 'existing-user', 'OCR-legacy', 1)")
        conn.execute("INSERT INTO medication_schedules (id, user_id, user_medicine_id, scheduled_date, scheduled_time) VALUES (1, 'existing-user', 1, '2026-09-21', '08:00')")
        conn.execute("INSERT INTO medication_logs (user_id, schedule_id, user_medicine_id, status) VALUES ('existing-user', 1, 1, 'TAKEN')")
        conn.execute("INSERT INTO heart_rate_logs (user_id, bpm, measured_at) VALUES ('existing-user', 72, '2026-09-21T08:00:00')")
        conn.execute("ALTER TABLE prescriptions DROP COLUMN registration_revision")
        conn.execute("ALTER TABLE heart_rate_logs DROP COLUMN client_request_id")
        conn.execute("ALTER TABLE guardians DROP COLUMN consent_verified_at")
    return path


def test_dry_run_preserves_source_and_apply_keeps_ids_and_historical_ocr_rows(legacy_db, tmp_path):
    original = legacy_db.read_bytes()
    result = prepare(legacy_db)
    assert result["mode"] == "dry-run"
    assert legacy_db.read_bytes() == original
    assert result["counts"]["medication_logs"] == 1
    backup_path = tmp_path / "before.db"
    assert prepare(legacy_db, apply=True, backup_path=backup_path)["mode"] == "applied"
    assert backup_path.exists()
    with sqlite3.connect(legacy_db) as conn:
        assert conn.execute("SELECT registration_revision FROM prescriptions WHERE id='original-rx'").fetchone()[0] == 1
        assert conn.execute("SELECT client_request_id FROM heart_rate_logs").fetchone()[0] is None
        assert conn.execute("SELECT id, status FROM medication_logs").fetchall() == [(1, "TAKEN")]
        assert conn.execute("SELECT medicine_code, is_active FROM user_medicines").fetchall() == [("OCR-legacy", 1)]
    with pytest.raises(FileExistsError):
        prepare(legacy_db, apply=True, backup_path=backup_path)


def test_incompatible_schema_rolls_back_without_replacing_existing_table(tmp_path, monkeypatch):
    path = tmp_path / "unsupported.db"
    with sqlite3.connect(path) as conn:
        conn.execute("CREATE TABLE users (id TEXT PRIMARY KEY, original_note TEXT)")
        conn.execute("INSERT INTO users VALUES ('original', 'keep')")
    monkeypatch.setattr(init_db, "DB_PATH", str(path))
    with pytest.raises(RuntimeError, match="reviewed migration"):
        init_db.initialize_database(preserve_records=True)
    with sqlite3.connect(path) as conn:
        assert conn.execute("SELECT * FROM users").fetchall() == [("original", "keep")]
        assert conn.execute("SELECT name FROM sqlite_master WHERE name LIKE 'legacy_%'").fetchall() == []
