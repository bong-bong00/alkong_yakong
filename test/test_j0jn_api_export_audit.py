import json
import sqlite3

import pytest

from scripts.audit_j0jn_api_export import FILES, audit


@pytest.fixture
def source(tmp_path):
    database = tmp_path / 'main.db'
    with sqlite3.connect(database) as connection:
        connection.executescript('''
            CREATE TABLE users(id TEXT PRIMARY KEY);
            CREATE TABLE prescriptions(id TEXT PRIMARY KEY,user_id TEXT,ocr_text TEXT);
            CREATE TABLE prescription_items(id TEXT PRIMARY KEY,prescription_id TEXT,medicine_code TEXT,dosage TEXT);
            INSERT INTO users VALUES('synthetic');
            INSERT INTO prescriptions VALUES('p1','synthetic','synthetic OCR');
            INSERT INTO prescription_items VALUES('i1','p1','100','0.5');
        ''')
    export = tmp_path / 'export'
    folder = export / 'synthetic'
    folder.mkdir(parents=True)
    (export / 'summary.json').write_text(json.dumps({'found_users': [{
        'user_id': 'synthetic', 'medicines_status': 200,
        'prescription_status': 200, 'today_status': 200,
    }]}), encoding='utf-8')
    rows = [{'id': 'p1', 'user_id': 'synthetic', 'ocr_text': 'synthetic OCR', 'items': [{
        'id': 'i1', 'prescription_id': 'p1', 'medicine_code': '100', 'dosage': '0.5',
    }]}]
    for name in FILES:
        data = rows if name == 'prescriptions.json' else {'medicines': []} if name == 'medicines.json' else []
        (folder / name).write_text(json.dumps(data), encoding='utf-8')
    return export, database, rows


def save_rows(export, rows):
    (export / 'synthetic' / 'prescriptions.json').write_text(json.dumps(rows), encoding='utf-8')


def test_matching_partial_export_is_not_full_migration_ready(source):
    export, database, _ = source
    before = database.read_bytes()
    result = audit(export, database)
    assert result['counts']['prescriptions_in_main'] == 1
    assert result['counts']['items_in_main'] == 1
    assert result['counts']['changed_items'] == 0
    assert result['full_medication_migration_ready'] is False
    assert 'synthetic OCR' not in json.dumps(result)
    assert database.read_bytes() == before


def test_changes_are_reported_without_values(source):
    export, database, rows = source
    rows[0]['items'][0]['dosage'] = 'private-different-value'
    save_rows(export, rows)
    result = audit(export, database)
    assert result['changed_fields']['items'] == {'dosage': 1}
    assert 'private-different-value' not in json.dumps(result)


def test_duplicate_identity_rejected(source):
    export, database, rows = source
    rows.append(rows[0])
    save_rows(export, rows)
    with pytest.raises(ValueError, match='duplicate prescription'):
        audit(export, database)


def test_wrong_owner_rejected(source):
    export, database, rows = source
    rows[0]['items'][0]['prescription_id'] = 'different'
    save_rows(export, rows)
    with pytest.raises(ValueError, match='owner mismatch'):
        audit(export, database)


def test_missing_file_rejected(source):
    export, database, _ = source
    (export / 'synthetic' / 'schedule-days.json').unlink()
    with pytest.raises(FileNotFoundError):
        audit(export, database)


def test_path_escape_rejected(source):
    export, database, _ = source
    (export / 'summary.json').write_text(json.dumps({'found_users': [{'user_id': '../outside'}]}), encoding='utf-8')
    with pytest.raises(ValueError, match='folder identity'):
        audit(export, database)
