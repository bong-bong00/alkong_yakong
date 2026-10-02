import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app import database
from app.models.schemas import OCRMedicineItem
from app.routes.prescription import router
from app.services import prescription_service as service
from init_db import TABLE_DEFINITIONS


@pytest.mark.parametrize('instruction', [None, '1일 1회 취침 전'])
def test_instruction_survives_ocr_model_validation(instruction):
    item = service._structured_items({'items': [{
        'drug_name': '테스트정', 'dosing_instruction': instruction,
    }]})[0]
    assert item.dosing_instruction == instruction
    assert item.model_dump()['dosing_instruction'] == instruction


@pytest.mark.parametrize('instruction', [None, '1일 1회 취침 전'])
def test_matched_ocr_preview_returns_200_instead_of_attribute_error(tmp_path, monkeypatch, instruction):
    monkeypatch.setattr(database, 'DB_PATH', str(tmp_path / 'ocr-preview.db'))
    conn = database.get_connection()
    for definition in TABLE_DEFINITIONS.values():
        conn.execute(definition)
    conn.execute(
        "INSERT INTO medicines (medicine_code, product_name, ingredient) VALUES ('TEST-OCR', '테스트정', '테스트성분')"
    )
    conn.commit()
    conn.close()
    item = OCRMedicineItem(
        drug_name='테스트정', medicine_code='TEST-OCR', dosage='1정',
        frequency_per_day=1, duration_days=7,
        dosing_instruction=instruction,
        administration_times=['취침전'] if instruction else [],
    )
    monkeypatch.setattr(service, '_extract_items', lambda _: ([item], '테스트정', {}, {}))
    monkeypatch.setattr(service, '_resolve_medicine', lambda *_: ('TEST-OCR', 'MATCHED', '테스트정'))
    monkeypatch.setattr(service, 'find_permission_product_by_item_seq', lambda *_: None)
    from app.services import dur_service
    monkeypatch.setattr(dur_service, 'preview_conflicts_for_codes', lambda *_: {})
    app = FastAPI()
    app.include_router(router)
    with TestClient(app) as client:
        response = client.post('/api/v1/prescriptions/ocr', json={
            'user_id': 'test-ocr-user', 'ocr_text': '테스트정 1정 1회 7일',
        })
    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload['registered'] is False
    assert payload['items'][0]['dosing_instruction'] == (instruction or '')
    if instruction:
        assert payload['items'][0]['administration_times'] == ['취침전']
    conn = database.get_connection()
    try:
        assert conn.execute('SELECT count(*) FROM user_medicines').fetchone()[0] == 0
    finally:
        conn.close()
