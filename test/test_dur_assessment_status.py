import sqlite3
import json
import logging

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


def test_diagnostic_records_generic_targets_without_personal_text(tmp_path, monkeypatch, caplog):
    db_path = tmp_path / "diagnostic.sqlite3"
    _prepare_db(db_path)
    monkeypatch.setattr(dur_service, "get_connection", lambda: _open_db(db_path))
    with caplog.at_level(logging.INFO, logger="uvicorn.error"):
        result = dur_service.analyze_dur(
            DurAnalyzeRequest(user_id="patient-1", medicine_codes=["MED-1"]),
            persist=False, refresh=False, diagnostic_id="test-trace",
        )
    events = [json.loads(record.getMessage().split(" ", 1)[1])
              for record in caplog.records if record.getMessage().startswith("[DUR_DIAG] {")]
    assert events[0]["trace_id"] == events[1]["trace_id"] == "test-trace"
    assert events[0]["medicines"] == [{"code": "MED-1", "ingredient_usable": True}]
    assert events[1]["taboo_row_count"] == 0
    assert events[1]["relevant_rule_count"] == 0
    assert events[1]["assessment_status"] == result["assessment_status"] == "INCOMPLETE"
    assert events[1]["pair_match_count"] == 0
    assert "patient-1" not in caplog.text
    assert "테스트정" not in caplog.text
    assert "테스트성분" not in caplog.text
    conn = _open_db(db_path)
    assert conn.execute("SELECT COUNT(*) FROM risk_results").fetchone()[0] == 0
    conn.close()


def test_diagnostic_records_failure_without_changing_exception(tmp_path, monkeypatch, caplog):
    import pytest
    from fastapi import HTTPException
    db_path = tmp_path / "failed-diagnostic.sqlite3"
    _prepare_db(db_path)
    monkeypatch.setattr(dur_service, "get_connection", lambda: _open_db(db_path))
    with caplog.at_level(logging.INFO, logger="uvicorn.error"):
        with pytest.raises(HTTPException) as caught:
            dur_service.analyze_dur(
                DurAnalyzeRequest(user_id="missing-private-user"),
                persist=False, refresh=False, diagnostic_id="failed-trace",
            )
    assert caught.value.status_code == 404
    assert "trace_id=failed-trace stage=error error_type=HTTPException" in caplog.text
    assert "missing-private-user" not in caplog.text


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
