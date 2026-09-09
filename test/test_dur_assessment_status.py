import sqlite3

from app.models.schemas import DurAnalyzeRequest
from app.models.response_schemas import DurAnalyzeResponse
from app.services import dur_service, dur_sync_service
from init_db import TABLE_DEFINITIONS


def _open_db(path):
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    return conn


def _prepare_db(path):
    conn = _open_db(path)
    for table in ("users", "medicines", "dur_taboo", "user_medicines", "risk_results"):
        conn.execute(TABLE_DEFINITIONS[table])
    conn.execute(
        "INSERT INTO users (id, name, birth_date) VALUES ('patient-1', '환자', '1950-01-01')"
    )
    conn.execute(
        """
        INSERT INTO medicines (medicine_code, product_name, ingredient)
        VALUES ('MED-1', '테스트정', '테스트성분')
        """
    )
    conn.execute(
        "INSERT INTO user_medicines (user_id, medicine_code) VALUES ('patient-1', 'MED-1')"
    )
    conn.commit()
    conn.close()


def test_missing_live_dur_source_is_incomplete_not_safe(tmp_path, monkeypatch):
    db_path = tmp_path / "dur.sqlite3"
    _prepare_db(db_path)
    monkeypatch.setattr(dur_service, "get_connection", lambda: _open_db(db_path))
    monkeypatch.setattr(
        dur_sync_service,
        "refresh_dur_for_ingredients",
        lambda _names: {"status": "skipped_missing_key", "fetched": 0, "upserted": 0},
    )

    result = dur_service.analyze_dur(DurAnalyzeRequest(user_id="patient-1"))

    assert result["assessment_status"] == "INCOMPLETE"
    assert result["risk_level"] == "UNKNOWN"
    assert result["analysis_complete"] is False
    assert "병용금기" in result["incomplete_types"]
    api_payload = DurAnalyzeResponse.model_validate(result).model_dump()
    assert api_payload["assessment_status"] == "INCOMPLETE"
    assert api_payload["incomplete_types"]


def test_completed_live_dur_check_can_report_safe(tmp_path, monkeypatch):
    db_path = tmp_path / "dur.sqlite3"
    _prepare_db(db_path)
    monkeypatch.setattr(dur_service, "get_connection", lambda: _open_db(db_path))
    monkeypatch.setattr(
        dur_sync_service,
        "refresh_dur_for_ingredients",
        lambda _names: {"status": "ok", "fetched": 0, "upserted": 0},
    )

    result = dur_service.analyze_dur(DurAnalyzeRequest(user_id="patient-1"))

    assert result["assessment_status"] == "SAFE"
    assert result["risk_level"] == "LOW"
    assert result["analysis_complete"] is True
    assert result["incomplete_types"] == []


def test_no_registered_medicine_is_a_valid_incomplete_api_response(tmp_path, monkeypatch):
    db_path = tmp_path / "dur.sqlite3"
    _prepare_db(db_path)
    conn = _open_db(db_path)
    conn.execute("DELETE FROM user_medicines")
    conn.commit()
    conn.close()
    monkeypatch.setattr(dur_service, "get_connection", lambda: _open_db(db_path))

    result = dur_service.analyze_dur(DurAnalyzeRequest(user_id="patient-1"))
    payload = DurAnalyzeResponse.model_validate(result).model_dump()

    assert payload["risk_result_id"] is None
    assert payload["analysis_id"] is None
    assert payload["assessment_status"] == "INCOMPLETE"
