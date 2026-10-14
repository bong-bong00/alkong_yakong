import json
import sqlite3

import pytest

from init_db import TABLE_DEFINITIONS
from scripts.audit_j0jn_api_export import FILES
from scripts.prepare_limited_medication import prepare
from scripts.migrate_neon_limited import check_manifest, inspect
from scripts.migrate_neon import Backup


@pytest.fixture
def recovery(tmp_path):
    source = tmp_path / 'main.db'
    with sqlite3.connect(source) as connection:
        for definition in TABLE_DEFINITIONS.values():
            connection.execute(definition)
        connection.execute("INSERT INTO users(id,name,role) VALUES('u','Synthetic','PATIENT')")
        connection.execute("INSERT INTO medicines(medicine_code,product_name,ingredient) VALUES('100','Synthetic drug','Synthetic ingredient')")
        connection.execute("INSERT INTO prescriptions(id,user_id,ocr_text) VALUES('p','u','Synthetic OCR')")
        connection.execute("INSERT INTO prescription_items(id,prescription_id,medicine_code,ocr_drug_name) VALUES(1,'p','100','Synthetic drug')")
        connection.execute("INSERT INTO user_medicines(id,user_id,medicine_code,prescription_item_id,start_date,end_date) VALUES(1,'u','100',1,'2000-01-01','2000-01-02')")
        connection.execute("INSERT INTO user_medicines(id,user_id,medicine_code) VALUES(2,'u','100')")
    export = tmp_path / 'export'
    folder = export / 'u'
    folder.mkdir(parents=True)
    (export / 'summary.json').write_text(json.dumps({'found_users': [{
        'user_id': 'u', 'medicines_status': 200, 'prescription_status': 200, 'today_status': 200,
    }]}), encoding='utf-8')
    rows = [{'id': 'p', 'user_id': 'u', 'ocr_text': 'Synthetic OCR', 'items': [{
        'id': 1, 'prescription_id': 'p', 'medicine_code': '100', 'ocr_drug_name': 'Synthetic drug',
    }]}]
    medicines = {'medicines': [{'user_medicine_id': 1, 'medicine_code': '100', 'status': 'active',
                               'dosage': '0.5', 'administration_times': ['08:00']}]}
    for name in FILES:
        value = rows if name == 'prescriptions.json' else medicines if name == 'medicines.json' else []
        (folder / name).write_text(json.dumps(value), encoding='utf-8')
    return source, export, tmp_path / 'candidate.db'


def test_partial_recovery_does_not_resurrect_unexported_medicines_or_logs(recovery):
    source, export, output = recovery
    original = source.read_bytes()
    result = prepare(export, source, output)
    assert source.read_bytes() == original
    assert result['copied_rows']['user_medicines'] == 1
    assert result['active_medicines'] == 1
    with sqlite3.connect(output) as connection:
        assert connection.execute('SELECT COUNT(*) FROM medication_schedules').fetchone()[0] == 0
        assert connection.execute('SELECT COUNT(*) FROM medication_logs').fetchone()[0] == 0
        assert connection.execute('SELECT start_date,end_date,dosage FROM user_medicines').fetchone() == (None, None, '0.5')
    manifest = check_manifest(source, output)
    main, medication = Backup(source), Backup(output)
    try:
        assert inspect(main, medication, manifest)['full_j0jn_restore'] is False
    finally:
        main.close()
        medication.close()


def test_existing_candidate_is_never_overwritten(recovery):
    source, export, output = recovery
    output.write_bytes(b'keep')
    with pytest.raises(ValueError, match='new output'):
        prepare(export, source, output)
    assert output.read_bytes() == b'keep'


def test_modified_candidate_fails_certificate(recovery):
    source, export, output = recovery
    prepare(export, source, output)
    with sqlite3.connect(output) as connection:
        connection.execute("UPDATE user_medicines SET dosage='changed'")
    with pytest.raises(ValueError, match='hash mismatch'):
        check_manifest(source, output)


@pytest.mark.parametrize('status,active', [('active', 1), ('past', 0)])
def test_current_and_past_are_distinct(recovery, status, active):
    source, export, output = recovery
    path = export / 'u' / 'medicines.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    data['medicines'][0]['status'] = status
    path.write_text(json.dumps(data), encoding='utf-8')
    prepare(export, source, output)
    with sqlite3.connect(output) as connection:
        assert connection.execute('SELECT status,is_active FROM user_medicines').fetchone() == (status.upper(), active)


def test_wrong_current_medicine_code_stops_before_output(recovery):
    source, export, output = recovery
    path = export / 'u' / 'medicines.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    data['medicines'][0]['medicine_code'] = 'wrong'
    path.write_text(json.dumps(data), encoding='utf-8')
    with pytest.raises(ValueError, match='identity/owner'):
        prepare(export, source, output)
    assert not output.exists()
