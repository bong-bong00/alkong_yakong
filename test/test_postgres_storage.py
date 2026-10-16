import os
import sqlite3
import uuid
from unittest.mock import Mock

import pytest

from app.postgres import Row, translate_sql, schema_for_role, validate_url, Connection, prepare_schema
from scripts.migrate_neon import Backup, audit, row_hash
from init_db import TABLE_DEFINITIONS, INDEXES


def test_named_and_indexed_rows_keep_repository_behavior():
    row = Row(['id', 'name', '_sqlite_rowid'], [7, '검증용', 99])
    assert dict(row) == {'id': 7, 'name': '검증용'}
    assert row[0] == 7 and row['NAME'] == '검증용'
    assert list(row) == [7, '검증용']


@pytest.mark.parametrize('role,schema', [('main','alkong_main'), ('medication','alkong_medication')])
def test_server_role_cannot_cross_schema(role, schema):
    assert schema_for_role(role) == schema


@pytest.mark.parametrize('role', ['unknown', 'public; DROP SCHEMA public', 'guardian'])
def test_invalid_role_fails_closed(role):
    with pytest.raises(ValueError): schema_for_role(role)


@pytest.mark.parametrize('url', ['', 'https://example.com/db', 'postgresql://example.com'])
def test_invalid_url_never_exposes_passwords(url):
    with pytest.raises(ValueError, match='NEON_DATABASE_URL'): validate_url(url)


def test_placeholder_translation_respects_quotes_and_percent_literals():
    converted = translate_sql("SELECT '?' AS literal, name FROM users WHERE id=? AND phone LIKE '010%' -- ?")
    assert "'?' AS literal" in converted and 'id=%s' in converted
    assert "'010%%'" in converted and '-- ?' in converted


def test_dialect_conversion_keeps_conflict_and_timestamp_semantics():
    assert translate_sql('INSERT OR IGNORE INTO users(id,name) VALUES(?,?)').endswith('ON CONFLICT DO NOTHING')
    assert 'sqlite_datetime(measured_at)' in translate_sql('SELECT * FROM heart_rate_logs ORDER BY datetime(measured_at)')
    with pytest.raises(sqlite3.OperationalError): translate_sql('INSERT OR REPLACE INTO users VALUES(?)')


def test_postgres_table_ddl_preserves_original_keys_and_uuid_revisions():
    text = translate_sql(TABLE_DEFINITIONS['prescriptions'])
    assert "registration_revision TEXT NOT NULL DEFAULT '1'" in text
    assert '_sqlite_rowid BIGINT GENERATED' in text
    assert 'id TEXT PRIMARY KEY' in text
    assert 'AUTOINCREMENT' not in translate_sql(TABLE_DEFINITIONS['medicines'])


def test_every_application_ddl_parses_as_postgres():
    parser = pytest.importorskip('pglast', reason='Optional PostgreSQL grammar checker is not installed')
    for definition in [*TABLE_DEFINITIONS.values(), *INDEXES]:
        parser.parse_sql(translate_sql(definition).replace('%%', '%'))


def make_backup(tmp_path, name, uid='shared-user'):
    path = tmp_path / name
    with sqlite3.connect(path) as connection:
        for definition in TABLE_DEFINITIONS.values(): connection.execute(definition)
        connection.execute('INSERT INTO users(id,name,role) VALUES(?,?,?)', (uid, '검증용', 'PATIENT'))
        connection.execute("INSERT INTO prescriptions(id,user_id,registration_revision) VALUES('rx',?,'uuid-revision')", (uid,))
    return path


def test_dry_run_is_read_only_and_preserves_both_colliding_ids(tmp_path):
    paths = [make_backup(tmp_path, name) for name in ['main.db', 'medication.db']]
    before = [path.read_bytes() for path in paths]
    main, medication = [Backup(path) for path in paths]
    try:
        result = audit(main, medication)
        assert result['network_access'] is False and result['unlinked_medication_users'] == 0
        assert result['source_counts']['main']['prescriptions'] == result['source_counts']['medication']['prescriptions'] == 1
    finally:
        main.close(); medication.close()
    assert before == [path.read_bytes() for path in paths]


def test_different_user_ids_are_reported_not_guessed(tmp_path):
    main = Backup(make_backup(tmp_path, 'main.db'))
    medication = Backup(make_backup(tmp_path, 'med.db', 'different-user'))
    try:
        assert audit(main, medication)['unlinked_medication_users'] == 1
    finally:
        main.close(); medication.close()


def test_unknown_tables_stop_import_instead_of_discarding_records(tmp_path):
    path = make_backup(tmp_path, 'main.db')
    with sqlite3.connect(path) as connection: connection.execute('CREATE TABLE legacy_records(id INTEGER)')
    with pytest.raises(ValueError, match='preservation plan'): Backup(path)


def test_hash_normalizes_only_legacy_revision_storage_type():
    assert row_hash([(1, 7)], ['registration_revision', 'id']) == row_hash([('1', 7)], ['registration_revision', 'id'])
    assert row_hash([(1, 7)], ['registration_revision', 'id']) != row_hash([('1', 8)], ['registration_revision', 'id'])


def test_nonempty_destination_is_never_overwritten(tmp_path, monkeypatch):
    import app.postgres as postgres
    from scripts.migrate_neon import apply_import
    main = Backup(make_backup(tmp_path, 'main.db'))
    medication = Backup(make_backup(tmp_path, 'med.db'))
    connection = Mock()
    connection.raw.execute.return_value.fetchall.return_value = [('users',)]
    connection.raw.execute.return_value.fetchone.return_value = (1,)
    monkeypatch.setattr(postgres, 'Connection', Mock(return_value=connection))
    try:
        with pytest.raises(ValueError, match='not empty'):
            apply_import(main, medication, 'postgresql://unused/unused')
        connection.commit.assert_not_called()
        connection.rollback.assert_called_once()
        connection.close.assert_called_once()
    finally:
        main.close(); medication.close()


def test_identity_mismatch_stops_before_network(tmp_path, monkeypatch):
    import app.postgres as postgres
    from scripts.migrate_neon import apply_import
    connect = Mock()
    monkeypatch.setattr(postgres, 'Connection', connect)
    main = Backup(make_backup(tmp_path, 'main.db'))
    medication = Backup(make_backup(tmp_path, 'med.db', 'different'))
    try:
        with pytest.raises(ValueError, match='reconciliation'):
            apply_import(main, medication, 'postgresql://unused/unused')
        connect.assert_not_called()
    finally:
        main.close(); medication.close()


def test_backend_opt_in_never_connects_by_url_presence_alone(monkeypatch):
    import app.database as database
    monkeypatch.setenv('NEON_DATABASE_URL', 'postgresql://test:test@example.invalid/db')
    monkeypatch.setenv('ALKONGYAKONG_DATABASE_BACKEND', 'sqlite')
    assert database.database_backend() == 'sqlite'


def test_connection_uses_tls_and_never_logs_credentials(monkeypatch):
    import psycopg
    raw = Mock()
    connect = Mock(return_value=raw)
    monkeypatch.setattr(psycopg, 'connect', connect)
    with Connection('postgresql://user:private@example.invalid/db?sslmode=disable', 'alkong_main'):
        assert connect.call_args.kwargs['sslmode'] == 'verify-full'
    assert raw.commit.called and raw.close.called


def test_new_connection_does_not_cache_committed_transaction_schema(monkeypatch):
    import psycopg
    raw = Mock()
    monkeypatch.setattr(psycopg, 'connect', Mock(return_value=raw))
    connection = Connection('postgresql://user:private@example.invalid/db', 'alkong_main')
    assert connection._transaction_schema is None
    raw.reset_mock()
    connection.execute('BEGIN IMMEDIATE')
    assert connection._transaction_schema == 'alkong_main'
    assert any('SET LOCAL search_path' in str(call) for call in raw.execute.call_args_list)
    connection.close()


def test_live_postgres_contract_in_disposable_schema():
    url = os.getenv('NEON_TEST_DATABASE_URL')
    if not url:
        pytest.skip('No dedicated PostgreSQL test URL; SQLite/unit tests are not a live Neon verification')
    from psycopg import sql
    schema = 'alkong_test_' + uuid.uuid4().hex
    connection = Connection(url, schema)
    created = False
    try:
        prepare_schema(connection)
        connection.commit()
        created = True
        connection.execute("INSERT INTO users(id,name,role) VALUES(?,?,?)", ('u', "한글? '문자' %", 'PATIENT'))
        cursor = connection.execute("INSERT INTO medicines(medicine_code,product_name,ingredient) VALUES('M','약','성분')")
        assert isinstance(cursor.lastrowid, int)
        connection.execute("INSERT OR IGNORE INTO medicines(medicine_code,product_name,ingredient) VALUES('M','중복','성분')")
        assert connection.execute("SELECT COUNT(*) FROM medicines").fetchone()[0] == 1
        import psycopg
        with psycopg.Cursor(connection.raw) as copy_cursor:
            with copy_cursor.copy('COPY medicines (medicine_code,product_name,ingredient) FROM STDIN') as writer:
                writer.write_row(('COPY', '검증약', '검증성분'))
        assert connection.execute('SELECT product_name FROM medicines WHERE medicine_code=?', ('COPY',)).fetchone()[0] == '검증약'
        connection.execute("INSERT INTO prescriptions(id,user_id,registration_revision) VALUES('rx','u','uuid-revision')")
        connection.commit()
        assert connection.execute('SELECT name FROM users WHERE id=?', ('u',)).fetchone()['name'] == "한글? '문자' %"
        assert 'registration_revision' in {row[1] for row in connection.execute('PRAGMA table_info(prescriptions)')}
        with pytest.raises(sqlite3.IntegrityError):
            connection.execute("INSERT INTO prescriptions(id,user_id) VALUES('orphan','missing')")
        assert connection.execute('SELECT COUNT(*) FROM prescriptions').fetchone()[0] == 1
        assert connection.execute("SELECT datetime('now', ?)", ('-1 day',)).fetchone()[0] is not None
    finally:
        connection.rollback()
        if created:
            # Unique schema created by this test ONLY; never drop app schemas.
            connection.raw.execute(sql.SQL('DROP SCHEMA {} CASCADE').format(sql.Identifier(schema)))
            connection.raw.commit()
        connection.close()
