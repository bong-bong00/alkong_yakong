import pytest

from app.services.pharmacist.retrieve import (
    search_official_medicine_candidates,
    search_live_official_candidates,
)


def _patch_api(monkeypatch, products):
    calls = []
    def fetch(**kwargs):
        calls.append(kwargs["item_name"])
        return {"products": products.get(kwargs["item_name"], [])}
    monkeypatch.setattr("app.services.mfds_drug_permission.client.fetch_permission_list_page", fetch)
    monkeypatch.setattr("app.services.mfds_drug_permission.client.extract_items", lambda payload: payload["products"])
    return calls


def test_empty_internal_db_still_searches_official_api(monkeypatch):
    monkeypatch.setattr("app.services.mfds_drug_permission.db.search_permission_names", lambda query, limit: [])
    _patch_api(monkeypatch, {"맥스노펜세미정": [{"ITEM_SEQ": "123", "ITEM_NAME": "맥스노펜세미정"}]})
    hits = search_official_medicine_candidates("맥스노펜세미정")
    assert hits[0]["medicine_code"] == "123"
    assert hits[0]["requires_confirmation"] is True


def test_ocr_typo_proposes_candidate_but_never_auto_confirms(monkeypatch):
    calls = _patch_api(monkeypatch, {
        "라신": [{"ITEM_SEQ": "456", "ITEM_NAME": "헤라신정250밀리그램"}],
    })
    hits = search_live_official_candidates("해라신정")
    assert "해라신정" in calls
    assert "라신" in calls
    assert hits[0]["official_product_name"] == "헤라신정250밀리그램"
    assert hits[0]["requires_confirmation"] is True


def test_candidate_ingredient_uses_verified_product_name(monkeypatch):
    _patch_api(monkeypatch, {"헤라신정": [{
        "ITEM_SEQ": "456", "ITEM_NAME": "헤라신정250밀리그램(클래리트로마이신)",
        "ITEM_INGR_NAME": "Clarithromycin",
    }]})
    hits = search_live_official_candidates("헤라신정")
    assert hits[0]["ingredient_name"] == "클래리트로마이신"


def test_candidates_without_official_code_are_excluded(monkeypatch):
    _patch_api(monkeypatch, {"테스트정": [{"ITEM_NAME": "테스트정"}]})
    assert search_live_official_candidates("테스트정") == []


def test_different_strength_and_form_are_not_candidates(monkeypatch):
    _patch_api(monkeypatch, {"테스트정": [
        {"ITEM_SEQ": "1", "ITEM_NAME": "테스트정500mg"},
        {"ITEM_SEQ": "2", "ITEM_NAME": "테스트캡슐250mg"},
    ]})
    assert search_live_official_candidates("테스트정250mg") == []


def test_api_failure_is_not_reported_as_empty_search(monkeypatch):
    def fail(**kwargs):
        raise TimeoutError()
    monkeypatch.setattr("app.services.mfds_drug_permission.client.fetch_permission_list_page", fail)
    with pytest.raises(RuntimeError, match="official_search_unavailable"):
        search_live_official_candidates("테스트정")


def test_successful_empty_search_is_not_network_failure(monkeypatch):
    _patch_api(monkeypatch, {})
    assert search_live_official_candidates("테스트정") == []


def test_http_200_with_official_error_is_not_empty_search(monkeypatch):
    monkeypatch.setattr(
        "app.services.mfds_drug_permission.client.fetch_permission_list_page",
        lambda **kwargs: {"header": {"resultCode": "30", "resultMsg": "error"}},
    )
    with pytest.raises(RuntimeError, match="official_search_unavailable"):
        search_live_official_candidates("테스트정")


@pytest.mark.parametrize("mode,reason", [
    ("candidate", "CANDIDATES_REQUIRE_CONFIRMATION"),
    ("empty", "NO_OFFICIAL_MATCH"),
    ("error", "OFFICIAL_SEARCH_UNAVAILABLE"),
])
def test_preview_preserves_unresolved_name_without_auto_registration(monkeypatch, mode, reason):
    from app.models.schemas import OCRMedicineItem, PrescriptionOCRRequest
    import app.services.prescription_service as service

    class FakeConnection:
        def cursor(self): return self
        def execute(self, *args): return self
        def fetchone(self): return {"id": "synthetic-user"}
        def commit(self): pass
        def rollback(self): pass
        def close(self): pass

    monkeypatch.setattr(service, "get_connection", FakeConnection)
    monkeypatch.setattr(service, "purge_ocr_placeholder_rows", lambda conn: None)
    monkeypatch.setattr(service, "_resolve_medicine", lambda cursor, item: None)
    monkeypatch.setattr(service, "_extract_items", lambda request: (
        [OCRMedicineItem(drug_name="해라신정", frequency_per_day=3)],
        "해라신정 1일 3회 나 일분", {}, {},
    ))
    monkeypatch.setattr("app.services.dur_service.preview_conflicts_for_codes", lambda *args: {})
    def search(query):
        if mode == "error": raise TimeoutError()
        if mode == "empty": return []
        return [{"medicine_code": "456", "product_name": "헤라신정250밀리그램",
                 "requires_confirmation": True}]
    monkeypatch.setattr(service, "search_live_official_candidates", search)
    result = service.create_prescription_from_ocr(PrescriptionOCRRequest(
        user_id="synthetic-user", ocr_text="synthetic",
    ))
    assert result["registered"] is False
    assert result["items"] == []
    assert result["unrecognized_names"] == ["해라신정"]
    detail = result["unrecognized_details"][0]
    assert detail["reason"] == reason
    assert detail["frequency_per_day"] == 3
    assert detail["duration_days"] is None
    if mode == "candidate":
        assert detail["candidates"][0]["requires_confirmation"] is True
