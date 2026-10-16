"""Explicit live smoke test using one disposable synthetic application account.

Never modifies an existing patient. The synthetic account and its own records
are removed through the authenticated account-purge workflow in finally.
Credentials and response bodies are not printed. Run only for an approved
cutover, not as part of ordinary automated tests.
"""
from datetime import datetime, timedelta, timezone
import argparse
import json
from pathlib import Path
import secrets
import sys
import time
import uuid

import requests

MAIN = 'https://alkong-yakong.onrender.com'
MEDICATION = 'https://alkong-yakong-medication.onrender.com'


def run(output):
    output = Path(output).resolve()
    root = Path(__file__).resolve().parents[1]
    if output.is_relative_to(root) or output.exists():
        raise ValueError('Use a new private report outside Git')
    results = []
    user_id, headers = None, {}
    nonce = uuid.uuid4().hex
    name = 'System QA Cutover ' + nonce
    password = secrets.token_urlsafe(24)
    # Clearly not an assigned telephone number; no SMS workflow is invoked.
    phone = '000' + str(secrets.randbelow(10**20)).zfill(20)
    failure = None
    cleanup = False

    def call(label, method, base, path, *, expected=200, authorized=True, **kwargs):
        started = time.monotonic()
        response = requests.request(method, base + path,
            headers=headers if authorized else {}, timeout=90, **kwargs)
        entry = {'check': label, 'status': response.status_code,
                 'expected': expected, 'seconds': round(time.monotonic() - started, 2)}
        results.append(entry)
        print(json.dumps(entry), flush=True)
        if response.status_code != expected:
            raise AssertionError('Unexpected HTTP status for ' + label)
        return response.json() if response.content and response.status_code != 204 else None

    try:
        for base, role in ((MAIN, 'main'), (MEDICATION, 'medication')):
            health = call(role + '_health', 'GET', base, '/health', authorized=False)
            if health.get('database') != 'postgresql:alkong_' + role or health.get('demo_seed_enabled'):
                raise AssertionError('Unexpected deployed storage/seed configuration')
        created = call('synthetic_registration', 'POST', MAIN, '/api/v1/users', authorized=False,
            json={'name': name, 'phone': phone, 'password': password, 'role': 'PATIENT'})
        user_id = created['id']
        if created.get('name') != name or not created.get('access_token'):
            raise AssertionError('Registration did not return the synthetic identity')
        headers = {'Authorization': 'Bearer ' + created['access_token']}
        state_path = output.with_suffix('.state.json')
        with state_path.open('x', encoding='utf-8') as state:
            json.dump({'created_by': 'qa_live_cutover', 'user_id': user_id, 'name': name}, state)
        login = call('password_login', 'POST', MAIN, '/api/v1/users/login', authorized=False,
                     json={'phone': phone, 'password': password})
        if login.get('id') != user_id or not login.get('access_token'):
            raise AssertionError('Login identity mismatch')
        headers = {'Authorization': 'Bearer ' + login['access_token']}
        call('unauthenticated_main_blocked', 'GET', MAIN, '/api/v1/users/' + user_id, expected=401, authorized=False)
        call('unauthenticated_medication_blocked', 'GET', MEDICATION,
             '/api/v1/users/' + user_id + '/medicines', expected=401, authorized=False)
        call('cross_user_blocked', 'GET', MAIN, '/api/v1/users/qa-other-' + nonce, expected=403)
        call('profile_read', 'GET', MAIN, '/api/v1/users/' + user_id)
        call('medication_identity_bridge', 'GET', MEDICATION, '/api/v1/users/' + user_id + '/medicines')
        request_id = 'cutover-' + nonce
        reading = call('heart_save', 'POST', MAIN, '/api/v1/biosignal/heart-rate',
            json={'user_id': user_id, 'bpm': 75, 'source': 'QA',
                  'measurement_context': 'general', 'client_request_id': request_id})
        duplicate = call('heart_idempotent_retry', 'POST', MAIN, '/api/v1/biosignal/heart-rate',
            json={'user_id': user_id, 'bpm': 75, 'source': 'QA',
                  'measurement_context': 'general', 'client_request_id': request_id})
        if not reading.get('heart_rate_log_id') or duplicate.get('heart_rate_log_id') != reading.get('heart_rate_log_id'):
            raise AssertionError('Heart retry created a duplicate')
        call('heart_summary', 'GET', MAIN, '/api/v1/users/' + user_id + '/biosignal/heart-summary?include_readings=true')
        day = datetime.now(timezone(timedelta(hours=9))).date().isoformat()
        prescription = call('synthetic_prescription_registration', 'POST', MEDICATION, '/api/v1/prescriptions/confirm',
            json={'user_id': user_id, 'prescribed_date': day, 'expire_date': day,
                  'ocr_text': 'Synthetic deployment verification only',
                  'items': [{'medicine_code': '197800210', 'drug_name': '아디팜정(히드록시진염산염)',
                             'dosage': '0.5', 'unit': '정', 'dose_amount': '0.5', 'dose_unit': '정',
                             'frequency_per_day': 1, 'duration_days': 1, 'administration_times': ['08:00']}]})
        if not prescription.get('registered') or prescription.get('schedule_count') != 1:
            raise AssertionError('Confirmed synthetic prescription did not create exactly one schedule')
        today = call('today_schedule_read', 'GET', MEDICATION, '/api/v1/users/' + user_id + '/today-medicines')
        schedule_ids = []
        def collect(value):
            if isinstance(value, dict):
                if isinstance(value.get('schedule_id'), int):
                    schedule_ids.append(value['schedule_id'])
                for nested in value.values():
                    collect(nested)
            elif isinstance(value, list):
                for nested in value:
                    collect(nested)
        collect(today)
        schedule_ids = list(set(schedule_ids))
        if len(schedule_ids) != 1:
            raise AssertionError('Synthetic schedule identity mismatch')
        batch = {'user_id': user_id, 'schedule_ids': schedule_ids}
        call('medication_complete', 'POST', MEDICATION, '/api/v1/medication-logs/batch', json=batch)
        call('medication_cancel', 'POST', MEDICATION, '/api/v1/medication-logs/batch/cancel', json=batch)
        call('prescription_read', 'GET', MEDICATION, '/api/v1/users/' + user_id + '/prescriptions')
        call('history_read', 'GET', MEDICATION, '/api/v1/users/' + user_id + '/medication-history?start=' + day + '&end=' + day)
        call('unrelated_ai_question', 'POST', MAIN, '/api/v1/drug-explain/chat',
             json={'user_id': user_id, 'message': '오늘 날씨를 알려주세요.'})
    except Exception as error:
        failure = type(error).__name__
    finally:
        if user_id and headers:
            try:
                identity = call('cleanup_identity_verification', 'GET', MAIN, '/api/v1/users/' + user_id)
                if identity.get('name') != name:
                    raise AssertionError('Synthetic cleanup ownership mismatch')
                call('synthetic_account_purge', 'DELETE', MAIN, '/api/v1/users/' + user_id, expected=204)
                cleanup = True
            except Exception as error:
                failure = failure or 'cleanup_' + type(error).__name__
    result = {'checks': results, 'success': failure is None,
              'failure_type': failure, 'synthetic_account_removed': cleanup,
              'existing_patients_modified': False}
    with output.open('x', encoding='utf-8') as report:
        json.dump(result, report, ensure_ascii=False, indent=2)
    print(json.dumps({key: value for key, value in result.items() if key != 'checks'}), flush=True)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        result = run(args.output)
        raise SystemExit(0 if result['success'] else 1)
    except Exception as error:
        print('Live cutover QA failed (' + type(error).__name__ + '); inspect private state for cleanup.', file=sys.stderr)
        raise SystemExit(1) from None
