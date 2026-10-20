import sqlite3
import time
from unittest.mock import Mock

import pytest
from fastapi import FastAPI, Depends, HTTPException
from fastapi.testclient import TestClient

from init_db import TABLE_DEFINITIONS
from app.core import auth
from app.routes import users, guardians, medication_logs, internal
from app.models.schemas import MedicationBatchRequest, HeartRateCreate
from app.services.medication_batch import update_batch
from app.services import biosignal_service, heart_reading, medication_gateway


@pytest.fixture
def db(tmp_path, monkeypatch):
    path = tmp_path / 'secured.db'
    conn = sqlite3.connect(path)
    for definition in TABLE_DEFINITIONS.values():
        conn.execute(definition)
    for uid, role in [('p', 'PATIENT'), ('other', 'PATIENT'), ('g', 'GUARDIAN'), ('pending', 'GUARDIAN')]:
        conn.execute('INSERT INTO users(id,name,role,phone) VALUES(?,?,?,?)', (uid, uid, role, uid))
    conn.execute("INSERT INTO guardians(id,user_id,guardian_name,guardian_user_id,status,consent_verified_at) VALUES('L','p','g','g','ACCEPTED',CURRENT_TIMESTAMP)")
    conn.execute("INSERT INTO guardians(id,user_id,guardian_name,guardian_user_id,status) VALUES('W','p','pending','pending','PENDING')")
    conn.execute("INSERT INTO medicines(medicine_code,product_name,ingredient) VALUES('M','시험약','시험성분')")
    conn.execute("INSERT INTO user_medicines(id,user_id,medicine_code) VALUES(1,'p','M')")
    for sid in [1, 2]:
        conn.execute("INSERT INTO medication_schedules(id,user_id,user_medicine_id,scheduled_date,scheduled_time) VALUES(?,'p',1,'2026-10-13',?)", (sid, f'08:0{sid}'))
    conn.commit()
    conn.close()
    import app.database
    monkeypatch.setattr(app.database, 'DB_PATH', str(path))
    monkeypatch.setenv('AUTH_ENFORCED', 'true')
    monkeypatch.setenv('ALKONGYAKONG_AUTH_SECRET', 'synthetic-test-key-not-used-for-production-123456')
    monkeypatch.setenv('SERVICE_ROLE', 'main')
    return path


def client():
    app = FastAPI()
    for router in [users.router, guardians.router, medication_logs.router, internal.router]:
        app.include_router(router, dependencies=[Depends(auth.require_authorized_request)])
    return TestClient(app)


def bearer(uid, role='PATIENT'):
    return {'Authorization': 'Bearer ' + auth.issue_token(uid, role=role)[0]}


def test_private_profile_requires_valid_owner_or_accepted_guardian(db):
    api = client()
    assert api.get('/api/v1/users/p').status_code == 401
    assert api.get('/api/v1/users/p', headers=bearer('other')).status_code == 403
    assert api.get('/api/v1/users/p', headers=bearer('pending', 'GUARDIAN')).status_code == 403
    assert api.get('/api/v1/users/p', headers=bearer('g', 'GUARDIAN')).status_code == 200
    assert api.get('/api/v1/guardians/users/p', headers=bearer('g', 'GUARDIAN')).status_code == 403
    assert api.get('/api/v1/users/p', headers=bearer('p')).status_code == 200
    assert api.patch('/api/v1/users/p', json={'name': 'changed'}, headers=bearer('g', 'GUARDIAN')).status_code == 403
    assert api.delete('/api/v1/users/p', headers=bearer('g', 'GUARDIAN')).status_code == 403


def test_guardian_cannot_accept_own_pending_link_or_record_patient_completion(db):
    api = client()
    assert api.patch('/api/v1/guardians/W', json={'status': 'ACCEPTED'}, headers=bearer('pending', 'GUARDIAN')).status_code == 403
    assert api.post('/api/v1/medication-logs/batch', json={'user_id': 'p', 'schedule_ids': [1]}, headers=bearer('g', 'GUARDIAN')).status_code == 403
    assert api.get('/api/v1/guardians/accounts/p/patients', headers=bearer('p')).status_code == 403


def test_tampering_expiry_and_missing_secret_fail_closed(db, monkeypatch):
    token = auth.issue_token('p', role='PATIENT')[0]
    with pytest.raises(HTTPException): auth.verify_token(token[:-4] + 'xxxx')
    monkeypatch.setattr(auth.time, 'time', lambda: 99999999999)
    with pytest.raises(HTTPException): auth.verify_token(token)
    monkeypatch.delenv('ALKONGYAKONG_AUTH_SECRET')
    assert client().get('/api/v1/users/p', headers={'Authorization': 'Bearer ' + token}).status_code == 503


def test_completion_and_cancel_are_atomic_and_preserve_audit(db):
    request = MedicationBatchRequest(user_id='p', schedule_ids=[1, 2])
    assert update_batch(request)['status'] == 'TAKEN'
    update_batch(request)
    conn = sqlite3.connect(db)
    assert conn.execute("SELECT COUNT(*) FROM medication_logs WHERE status='TAKEN'").fetchone()[0] == 2
    conn.close()
    update_batch(request, undo=True)
    conn = sqlite3.connect(db)
    assert conn.execute("SELECT COUNT(*) FROM medication_logs WHERE status='CANCELLED'").fetchone()[0] == 2
    assert conn.execute("SELECT COUNT(*) FROM medication_schedules WHERE status='PENDING'").fetchone()[0] == 2
    conn.close()
    with pytest.raises(HTTPException):
        update_batch(MedicationBatchRequest(user_id='p', schedule_ids=[1, 999]))
    conn = sqlite3.connect(db)
    assert conn.execute("SELECT COUNT(*) FROM medication_schedules WHERE status='TAKEN'").fetchone()[0] == 0
    conn.close()


@pytest.mark.parametrize('bpm,kind', [(59,'LOW_HEART_RATE'), (60,None), (100,None), (101,'HIGH_HEART_RATE')])
def test_60_to_100_policy_and_in_app_notice_only_for_accepted_guardian(db, bpm, kind):
    result = biosignal_service.save_heart_rate(HeartRateCreate(user_id='p', bpm=bpm))
    assert (result['abnormal_event'] or {}).get('event_type') == kind
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    assert heart_reading.latest_heart_reading(conn, 'p')['normal'] == (kind is None)
    assert conn.execute('SELECT COUNT(*) FROM notifications').fetchone()[0] == (1 if kind else 0)
    conn.close()


def test_gateway_failure_never_substitutes_main_database(db, monkeypatch):
    import requests
    monkeypatch.setattr(medication_gateway, 'MEDICATION_FEATURE_BASE_URL', 'https://med.example')
    monkeypatch.setattr(medication_gateway.requests, 'get', Mock(side_effect=requests.Timeout()))
    with pytest.raises(HTTPException) as error:
        medication_gateway.medication_get('p', '/today-medicines', local=lambda: {'doses': ['WRONG']})
    assert error.value.status_code == 503


def test_heart_retry_does_not_duplicate_records_or_notices(db):
    request = HeartRateCreate(user_id='p', bpm=105, client_request_id='same-operation')
    first = biosignal_service.save_heart_rate(request)
    second = biosignal_service.save_heart_rate(request)
    assert first['heart_rate_log_id'] == second['heart_rate_log_id']
    conn = sqlite3.connect(db)
    assert conn.execute('SELECT COUNT(*) FROM heart_rate_logs').fetchone()[0] == 1
    assert conn.execute('SELECT COUNT(*) FROM abnormal_events').fetchone()[0] == 1
    assert conn.execute('SELECT COUNT(*) FROM notifications').fetchone()[0] == 1
    conn.close()


def test_medication_service_reads_main_authority_and_mirrors_only_health_fields(db, monkeypatch):
    monkeypatch.setenv('SERVICE_ROLE', 'medication')
    monkeypatch.setenv('AUTH_AUTHORITY_BASE_URL', 'https://main.example')
    profile = Mock(status_code=200)
    profile.json.return_value = {'id': 'p', 'name': '환자', 'role': 'PATIENT', 'birth_date': '1950-05-05',
                                 'is_pregnant': True, 'phone': 'NOT_MIRRORED', 'password_hash': 'NOT_MIRRORED'}
    calls = Mock(return_value=profile)
    monkeypatch.setattr(auth.requests, 'get', calls)
    response = client().get('/api/v1/users/p', headers=bearer('p'))
    assert response.status_code == 200
    assert response.json()['birth_date'] == '1950-05-05'
    conn = sqlite3.connect(db)
    assert conn.execute('SELECT phone,password_hash FROM users WHERE id=?', ('p',)).fetchone() == ('p', None)
    conn.close()
    assert calls.call_count == 1


def test_internal_purge_rejects_user_tokens_and_is_idempotent_for_trusted_service(db, monkeypatch):
    monkeypatch.setenv('SERVICE_ROLE', 'medication')
    api = client()
    assert api.delete('/api/v1/internal/users/p', headers=bearer('p')).status_code == 403
    headers = auth.service_headers('p', 'account_purge')
    assert api.delete('/api/v1/internal/users/p', headers=headers).status_code == 204
    assert api.delete('/api/v1/internal/users/p', headers=headers).status_code == 204


def test_main_account_is_preserved_when_medication_purge_fails(db, monkeypatch):
    import requests
    import app.core.config as config
    monkeypatch.setattr(config, 'MEDICATION_FEATURE_BASE_URL', 'https://med.example')
    monkeypatch.setattr(requests, 'delete', Mock(side_effect=requests.Timeout()))
    assert client().delete('/api/v1/users/p', headers=bearer('p')).status_code == 503
    with sqlite3.connect(db) as conn:
        assert conn.execute("SELECT 1 FROM users WHERE id='p'").fetchone()


def test_synthetic_heart_data_does_not_create_guardian_notice(db):
    result = biosignal_service.save_heart_rate(HeartRateCreate(user_id='p', bpm=125, source='DEMO'))
    assert result['abnormal_event'] is None
    with sqlite3.connect(db) as conn:
        assert conn.execute('SELECT COUNT(*) FROM notifications').fetchone()[0] == 0


def test_latest_heart_uses_absolute_time_when_utc_and_kst_records_mix(db):
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    conn.execute("INSERT INTO heart_rate_logs(user_id,bpm,measured_at) VALUES('p',70,'2026-10-13T12:05:00+09:00')")
    conn.execute("INSERT INTO heart_rate_logs(user_id,bpm,measured_at) VALUES('p',80,'2026-10-13T05:00:00+00:00')")
    conn.commit()
    assert heart_reading.latest_heart_reading(conn, 'p')['bpm'] == 80
    conn.close()


def test_legacy_phone_only_contact_requires_patient_reacceptance(db):
    conn = sqlite3.connect(db)
    conn.execute("UPDATE users SET phone='01033334444' WHERE id='pending'")
    conn.execute("INSERT INTO guardians(id,user_id,guardian_name,phone,status) VALUES('legacy','other','가족','01033334444','ACCEPTED')")
    conn.commit()
    conn.close()
    api = client()
    headers = bearer('pending', 'GUARDIAN')
    assert api.get('/api/v1/users/other', headers=headers).status_code == 403
    result = api.get('/api/v1/guardians/accounts/pending/patients', headers=headers)
    assert result.status_code == 200 and result.json()['patients'] == []
    assert api.get('/api/v1/users/other', headers=headers).status_code == 403
