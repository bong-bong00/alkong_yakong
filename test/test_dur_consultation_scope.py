"""상담 범위와 저장 분리 검증. 실제 Render/식약처는 호출하지 않는다."""

import sqlite3

import pytest
from fastapi import HTTPException

from app.models.schemas import DurAnalyzeRequest
from app.routes import dur_analysis
from app.services import dur_service, dur_sync_service, external_api_service
from app.services.mfds_drug_permission import client, db
from init_db import TABLE_DEFINITIONS


def _open_db(path):
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    return conn


def _prepare_db(path):
    with _open_db(path) as conn:
        for table in ("users", "medicines", "dur_taboo", "user_medicines", "risk_results"):
            conn.execute(TABLE_DEFINITIONS[table])
        conn.execute("INSERT INTO users (id, name, birth_date) VALUES ('patient-1', '환자', '1950-01-01')")
        conn.execute("INSERT INTO medicines (medicine_code, product_name, ingredient) VALUES ('MED-1', '테스트정', '테스트성분')")
        conn.execute("INSERT INTO user_medicines (user_id, medicine_code) VALUES ('patient-1', 'MED-1')")


@pytest.fixture
def database(tmp_path, monkeypatch):
    path = tmp_path / "consultation.sqlite3"
    _prepare_db(path)
    monkeypatch.setattr(dur_service, "get_connection", lambda: _open_db(path))
    monkeypatch.setattr(db, "find_permission_product_by_item_seq", lambda code: None)
    monkeypatch.setattr(client, "fetch_permission_detail", lambda **kwargs: None)
    monkeypatch.setattr(external_api_service, "fetch_e_drug_info", lambda **kwargs: None)
    monkeypatch.setattr(dur_sync_service, "refresh_dur_for_ingredients",
                        lambda names: {"status": "ok", "fetched": 0, "upserted": 0})
    return path


def request(**kwargs):
    return DurAnalyzeRequest(
        user_id="patient-1", medicine_codes=["MED-1", "MED-2"],
        medicine_names_by_code={"MED-1": "테스트정", "MED-2": "두번째정"},
        analysis_purpose="consultation", **kwargs,
    )


def test_name_lookup_caches_catalog_without_registering_or_saving_result(database, monkeypatch):
    calls = []

    def lookup(**kwargs):
        calls.append(kwargs)
        return {"ITEM_SEQ": "MED-2", "ITEM_NAME": "두번째정", "MAIN_ITEM_INGR": "테스트성분"}

    monkeypatch.setattr(client, "fetch_permission_detail", lookup)
    result = dur_analysis.analyze(request())
    assert calls == [{"item_name": "두번째정", "item_seq": "MED-2"}]
    assert set(result["medicine_names"]) == {"테스트정", "두번째정"}
    assert result["has_risk"] is True  # 동일 성분 경고 유지
    assert result["analysis_complete"] is True
    with _open_db(database) as conn:
        assert conn.execute("SELECT COUNT(*) FROM medicines").fetchone()[0] == 2
        assert conn.execute("SELECT COUNT(*) FROM user_medicines").fetchone()[0] == 1
        assert conn.execute("SELECT COUNT(*) FROM risk_results").fetchone()[0] == 0


@pytest.mark.parametrize("candidate", [
    None,
    {"ITEM_SEQ": "OTHER", "ITEM_NAME": "두번째정", "MAIN_ITEM_INGR": "테스트성분"},
    {"ITEM_SEQ": "MED-2", "ITEM_NAME": "다른정", "MAIN_ITEM_INGR": "테스트성분"},
    {"ITEM_SEQ": "MED-2", "ITEM_NAME": "두번째정", "MAIN_ITEM_INGR": ""},
])
def test_unverified_or_missing_medicine_cannot_be_safe(database, monkeypatch, candidate):
    monkeypatch.setattr(client, "fetch_permission_detail", lambda **kwargs: candidate)
    result = dur_analysis.analyze(request())
    assert result["assessment_status"] == "INCOMPLETE"
    assert result["analysis_complete"] is False
    assert "중복성분" in result["incomplete_types"]
    assert result["medicine_names"] == ["테스트정"]


def test_existing_wrong_name_is_not_accepted(database):
    result = dur_analysis.analyze(DurAnalyzeRequest(
        user_id="patient-1", medicine_codes=["MED-1"],
        medicine_names_by_code={"MED-1": "다른제품정"}, analysis_purpose="consultation",
    ))
    assert result["analysis_complete"] is False
    assert result["medicine_names"] == []


def test_missing_target_does_not_hide_confirmed_duplicate_warning(database):
    with _open_db(database) as conn:
        conn.execute("INSERT INTO medicines (medicine_code, product_name, ingredient) VALUES ('MED-3', '세번째정', '테스트성분')")
    result = dur_analysis.analyze(DurAnalyzeRequest(
        user_id="patient-1", medicine_codes=["MED-1", "MED-2", "MED-3"],
        medicine_names_by_code={"MED-1": "테스트정", "MED-2": "두번째정", "MED-3": "세번째정"},
        analysis_purpose="consultation",
    ))
    assert result["assessment_status"] == "RISK_FOUND"
    assert result["has_risk"] is True
    assert result["analysis_complete"] is False
    assert any(match["type"] == "중복성분" for match in result["matches"])


def test_consultation_keeps_existing_home_result_and_normal_request_still_saves(database):
    original = dur_analysis.analyze(DurAnalyzeRequest(user_id="patient-1"))
    assert original["risk_result_id"] is not None
    dur_analysis.analyze(request())
    with _open_db(database) as conn:
        rows = conn.execute("SELECT id FROM risk_results").fetchall()
        assert [row["id"] for row in rows] == [original["risk_result_id"]]


@pytest.mark.parametrize("codes,names", [([], {}), (["MED-1"], {}), (["MED-1"], {"MED-1": " "})])
def test_consultation_requires_explicit_scope(database, codes, names):
    with pytest.raises(HTTPException) as caught:
        dur_analysis.analyze(DurAnalyzeRequest(
            user_id="patient-1", medicine_codes=codes, medicine_names_by_code=names,
            analysis_purpose="consultation",
        ))
    assert caught.value.status_code == 422


def test_legacy_code_request_with_missing_row_is_incomplete(database):
    result = dur_service.analyze_dur(DurAnalyzeRequest(
        user_id="patient-1", medicine_codes=["MED-1", "MISSING"],
    ), persist=False, refresh=True)
    assert result["analysis_complete"] is False


def test_lookup_failure_does_not_leak_private_text(database, monkeypatch, caplog):
    def failed(**kwargs):
        raise RuntimeError("private product and user")
    monkeypatch.setattr(client, "fetch_permission_detail", failed)
    result = dur_analysis.analyze(request())
    assert result["analysis_complete"] is False
    assert "private product and user" not in caplog.text


def test_local_catalog_failure_still_tries_official_name_lookup(database, monkeypatch):
    def failed(code):
        raise sqlite3.OperationalError("missing table")
    monkeypatch.setattr(db, "find_permission_product_by_item_seq", failed)
    monkeypatch.setattr(client, "fetch_permission_detail", lambda **kwargs: {
        "ITEM_SEQ": "MED-2", "ITEM_NAME": "두번째정", "MAIN_ITEM_INGR": "다른성분",
    })
    result = dur_analysis.analyze(request())
    assert result["analysis_complete"] is True
    assert result["assessment_status"] == "SAFE"
    assert len(result["medicine_names"]) == 2
