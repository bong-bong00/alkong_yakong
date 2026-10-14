import sqlite3
from scripts.audit_sqlite_backup import inspect_backup
from init_db import TABLE_DEFINITIONS


def make_backup(tmp_path, name):
    path = tmp_path / name
    with sqlite3.connect(path) as connection:
        for definition in TABLE_DEFINITIONS.values():
            connection.execute(definition)
        connection.execute("INSERT INTO users(id,name,role) VALUES('test','test','PATIENT')")
    return path


def test_single_backup_audit_is_read_only_and_never_claims_cutover_ready(tmp_path):
    path = make_backup(tmp_path, 'operating.db')
    before = path.read_bytes()
    result = inspect_backup(path)
    assert result['single_backup_schema_ready']
    assert not result['cutover_ready'] and not result['network_access']
    assert result['source_unchanged'] and path.read_bytes() == before


def test_legacy_rows_are_counted_but_never_exposed_or_silently_discarded(tmp_path):
    path = make_backup(tmp_path, 'operating.db')
    with sqlite3.connect(path) as connection:
        connection.execute('CREATE TABLE legacy_users(id TEXT, private_name TEXT)')
        connection.execute("INSERT INTO legacy_users VALUES('old', 'private-patient-name')")
    result = inspect_backup(path)
    assert result['table_counts']['legacy_users'] == 1
    assert result['tables_requiring_preservation_plan'] == ['legacy_users']
    assert not result['single_backup_schema_ready']
    assert 'private-patient-name' not in str(result)


def test_new_required_unique_constraints_are_checked_without_exposing_values(tmp_path):
    path = make_backup(tmp_path, 'operating.db')
    with sqlite3.connect(path) as connection:
        connection.execute('ALTER TABLE medicines RENAME TO discarded_medicines')
        connection.execute('CREATE TABLE medicines(id INTEGER, medicine_code TEXT)')
        connection.executemany('INSERT INTO medicines VALUES(?,?)', [(1, 'PRIVATE'), (2, 'PRIVATE')])
    result = inspect_backup(path)
    assert any(c['columns'] == ['medicine_code'] and c['duplicate_groups'] == 1 for c in result['unique_conflicts'])
    assert 'PRIVATE' not in str(result)
    assert not result['single_backup_schema_ready']
