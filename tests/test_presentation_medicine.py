import pytest
from fastapi import HTTPException

from init_db import TABLE_DEFINITIONS
from app.services.seed_mvp_medicines import ensure_presentation_codarone


def test_presentation_seed_all_patients_idempotent_and_preserves_existing(tmp_path, monkeypatch):
    from app import database

    path = tmp_path / 'presentation.db'
    monkeypatch.setattr(database, 'DB_PATH', str(path))
    conn = database.get_connection()
    for table in ('users', 'medicines', 'prescriptions', 'prescription_items',
                  'user_medicines', 'medication_schedules'):
        conn.execute(TABLE_DEFINITIONS[table])
    conn.execute("INSERT INTO users (id, name) VALUES ('first', '첫 사용자')")
    conn.execute("INSERT INTO medicines (medicine_code, product_name, ingredient) VALUES ('REAL', '기존약', '기존성분')")
    conn.execute("INSERT INTO user_medicines (user_id, medicine_code) VALUES ('first', 'REAL')")
    conn.commit()
    conn.close()

    for user in ('first', 'second'):
        ensure_presentation_codarone(user)
        ensure_presentation_codarone(user)
    conn = database.get_connection()
    try:
        for user in ('first', 'second'):
            assert conn.execute(
                "SELECT count(*) FROM user_medicines WHERE user_id=? AND medicine_code='200701021'",
                (user,),
            ).fetchone()[0] == 1
        assert conn.execute("SELECT is_active FROM user_medicines WHERE medicine_code='REAL'").fetchone()[0] == 1
        from app.services.today_medication_service import _ensure_today_schedules
        _ensure_today_schedules(conn, 'second', '2026-10-02')
        _ensure_today_schedules(conn, 'second', '2026-10-02')
        assert conn.execute("SELECT count(*) FROM medication_schedules WHERE user_id='second'").fetchone()[0] == 3
    finally:
        conn.close()


def test_presentation_endpoint_requires_server_switch_and_debug_header(monkeypatch):
    from app.core import config
    from app.routes.users import presentation_medicine

    monkeypatch.setattr(config, 'PRESENTATION_SEED_ENABLED', False)
    with pytest.raises(HTTPException) as error:
        presentation_medicine('first', 'debug')
    assert error.value.status_code == 404
    monkeypatch.setattr(config, 'PRESENTATION_SEED_ENABLED', True)
    with pytest.raises(HTTPException):
        presentation_medicine('first', None)
