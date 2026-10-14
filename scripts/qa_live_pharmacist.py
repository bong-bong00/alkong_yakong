"""Explicit live Gemini/MFDS QA using a synthetic user and a disposable local DB.

Run with provider credentials in environment. Never targets an operating user
DB, registers a prescription, or deploys a service. Private result files stay
outside Git. A local DUR bridge is NOT a production two-server integration test.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import sqlite3
import sys
import time

ROOT = Path(os.getenv('ALKONG_QA_PROJECT_ROOT', str(Path(__file__).resolve().parents[1]))).resolve()
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

MEDICINES = [
    {'medicine_code': '197800210', 'product_name': '아디팜정(히드록시진염산염)'},
    {'medicine_code': '197800308', 'product_name': '프리마란정(메퀴타진)'},
    {'medicine_code': '200403137', 'product_name': '휴온스시메티딘정200밀리그램(수출명:TAGAMENTTab.200밀리그램)'},
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    parser.add_argument('--source-db', help='Read ONLY public DUR rows from this operating snapshot')
    parser.add_argument('--case', action='append', help='Run only the selected intent(s); repeatable')
    args = parser.parse_args()
    output = Path(args.output).resolve()
    if output.is_relative_to(ROOT) or output.exists():
        raise SystemExit('Use a new private output outside the repository')
    db = output.parent / 'qa-ai-synthetic.db'
    if db.exists():
        raise SystemExit('Disposable QA DB already exists')
    os.close(os.open(db, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
    os.environ.update({'ALKONGYAKONG_DB_PATH': str(db), 'ALKONGYAKONG_DATABASE_BACKEND': 'sqlite',
        'AUTH_ENFORCED': 'true', 'SERVICE_ROLE': 'main', 'APP_ENV': 'test',
        'ALKONGYAKONG_AUTH_SECRET': secrets.token_hex(32), 'PRESENTATION_SEED_ENABLED': 'false',
        'DEMO_SEED_ENABLED': 'false', 'DUR_AUTO_SYNC': 'false',
        'MFDS_DRUG_PERMISSION_DB_PATH': str(output.parent / 'qa-mfds.db'),
        'EASY_CATEGORY_MAP_DB_PATH': str(output.parent / 'qa-easy.db')})
    from init_db import TABLE_DEFINITIONS
    user_id = 'qa-synthetic-' + secrets.token_hex(8)
    with sqlite3.connect(db) as connection:
        for definition in TABLE_DEFINITIONS.values():
            connection.execute(definition)
        connection.execute('INSERT INTO users(id,name,role,birth_date,diseases,past_illnesses,allergies,smoking,drinking) '
            'VALUES(?,?,?,?,?,?,?,?,?)', (user_id, 'Synthetic QA', 'PATIENT', '1950-05-05',
            json.dumps(['신장질환', '당뇨', '천식']), json.dumps(['고혈압']), json.dumps(['페니실린']), '폈어요', '자주 마셔요'))
        if args.source_db:
            source_path = Path(args.source_db).resolve(strict=True)
            if source_path == db:
                raise SystemExit('Source and QA DB must differ')
            source = sqlite3.connect(source_path.as_uri() + '?mode=ro', uri=True)
            try:
                columns = [r[1] for r in source.execute('PRAGMA table_info(dur_taboo)')]
                target_columns = {r[1] for r in connection.execute('PRAGMA table_info(dur_taboo)')}
                if not set(columns) <= target_columns:
                    raise SystemExit('Public DUR schema is incompatible')
                quoted = ','.join('"' + c.replace('"', '""') + '"' for c in columns)
                connection.executemany('INSERT INTO dur_taboo (' + quoted + ') VALUES (' + ','.join('?' for _ in columns) + ')',
                    source.execute('SELECT ' + quoted + ' FROM dur_taboo').fetchall())
            finally:
                source.close()
    from fastapi import FastAPI, Depends
    from fastapi.testclient import TestClient
    from app.core.auth import require_authorized_request, issue_token
    from app.routes.drug_explain import router
    from app.services import gemini_service as gemini, medication_feature_dur_client as gateway
    from app.services.dur_service import analyze_dur
    from app.models.schemas import DurAnalyzeRequest
    import logging
    logging.getLogger('uvicorn.error').setLevel(logging.ERROR)
    # Explicit scope only, using the actual medication analysis code in the QA DB.
    def local_consultation(**kwargs):
        items = kwargs.get('additional_medicines') or []
        if kwargs.get('selected_medicine'):
            items = [kwargs['selected_medicine'], *items]
        request = DurAnalyzeRequest(user_id=user_id, medicine_codes=[m['medicine_code'] for m in items],
            medicine_names_by_code={m['medicine_code']: m['product_name'] for m in items}, analysis_purpose='consultation')
        data = analyze_dur(request, persist=False, refresh=True)
        matches = [m for m in data.get('matches', []) if m.get('type') in kwargs.get('requested_types', set())]
        complete = data.get('analysis_complete') is True and not data.get('incomplete')
        return {'status': 'current' if complete else 'incomplete', 'items': matches,
            'has_risk': bool(matches) if complete or matches else None,
            'zero_result_types': list(kwargs.get('requested_types', set())) if complete and not matches else [],
            'reason': None if complete else 'qa_analysis_incomplete'}
    gateway.load_remote_combination_context = local_consultation
    provider = {'calls': 0, 'successes': 0}
    original = gemini._generate_content_with_retry
    def tracked(*a, **k):
        provider['calls'] += 1
        response = original(*a, **k)
        provider['successes'] += 1
        return response
    gemini._generate_content_with_retry = tracked
    app = FastAPI(dependencies=[Depends(require_authorized_request)])
    app.include_router(router)
    token, _ = issue_token(user_id, role='patient')
    headers = {'Authorization': 'Bearer ' + token}
    client = TestClient(app)
    cases = [
        ('efficacy', '아디팜정이 어디에 쓰는 약인지 쉬운 말로 알려주세요.', [MEDICINES[0]]),
        ('dosage', '아디팜정을 언제 어떻게 먹는지 쉬운 말로 알려주세요.', [MEDICINES[0]]),
        ('precautions', '아디팜정을 먹을 때 무엇을 조심해야 하는지 알려주세요.', [MEDICINES[0]]),
        ('side_effects', '아디팜정을 먹은 뒤 평소와 다른 증상이 생기면 어떻게 해야 하나요?', [MEDICINES[0]]),
        ('combination', '이 세 약을 함께 먹을 때 주의할 점이 있는지 확인해 주세요.', MEDICINES),
        ('duplicate', '이 세 약 사이에 같은 성분이나 비슷한 역할이 겹치는지 확인해 주세요.', MEDICINES),
        ('health_precautions', '등록한 질환, 과거력, 알레르기, 흡연과 음주 정보를 참고해 주의할 점을 알려주세요.', MEDICINES),
        (None, '오늘 날씨와 주식 가격을 알려주세요.', [MEDICINES[0]]),
    ]
    results = []
    for index, (intent, message, selected) in enumerate(cases):
        if args.case and (intent or 'off_topic') not in args.case:
            continue
        body = {'user_id': user_id, 'message': message}
        if len(selected) == 1:
            body['selected_medicine'] = selected[0]
        else:
            body['selected_medicines'] = selected
        if intent:
            body['intent'] = intent
        before = provider.copy()
        started = time.monotonic()
        response = client.post('/api/v1/drug-explain/chat', json=body, headers=headers)
        data = response.json()
        reply = data.get('reply', '')
        entry = {'intent': intent, 'status_code': response.status_code, 'reply': reply,
            'sources': data.get('sources', []), 'highlights': data.get('health_highlight_terms', []),
            'medicine_count': len(data.get('conversation_medicines', [])), 'chars': len(reply),
            'elapsed_seconds': round(time.monotonic()-started, 2),
            'provider_calls': provider['calls']-before['calls'], 'provider_successes': provider['successes']-before['successes']}
        results.append(entry)
        print(json.dumps({k: v for k, v in entry.items() if k not in {'reply', 'sources', 'highlights'}}, ensure_ascii=True), flush=True)
    unauth = client.post('/api/v1/drug-explain/chat', json={'user_id': user_id, 'message': '안녕'})
    cross = client.post('/api/v1/drug-explain/chat', json={'user_id': 'different-user', 'message': '안녕'}, headers=headers)
    result = {'synthetic_profile': True, 'medication_bridge': 'isolated local QA code, not live j0jn',
        'unauth_status': unauth.status_code, 'cross_user_status': cross.status_code,
        'provider_totals': provider, 'cases': results}
    with os.fdopen(os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w', encoding='utf-8') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Live pharmacist QA failed (' + type(error).__name__ + ')', file=sys.stderr)
        raise SystemExit(1) from None
