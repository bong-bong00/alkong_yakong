from unittest.mock import MagicMock
import sqlite3
import pytest
from init_db import TABLE_DEFINITIONS
from scripts.migrate_neon import Backup, audit
from scripts.legacy_archive import encode_row, decode_row, legacy_snapshot, payload_hash, write_legacy_archive
from scripts.audit_sqlite_backup import inspect_backup

LEGACY = 'legacy_users_20260614222707'


def fixture_backup(tmp_path, name):
    path = tmp_path / name
    with sqlite3.connect(path) as conn:
        for ddl in TABLE_DEFINITIONS.values():
            conn.execute(ddl)
        conn.execute("INSERT INTO users(id,name,role) VALUES('new','test','PATIENT')")
        conn.execute(f'CREATE TABLE {LEGACY}(id INTEGER, user_id INTEGER, text_value TEXT, bytes_value BLOB)')
        conn.execute(f'INSERT INTO {LEGACY} VALUES(?,?,?,?)', (91, 456, 'private old name', b'\x00\xff'))
    return path


def test_codec_preserves_sqlite_types_and_large_integers():
    row = (None, 2**62, -0.0, 1.234567890123456, '한글\n? %', b'\x00\xff')
    result = decode_row(encode_row(row))
    assert result == row
    assert result[2].hex() == row[2].hex()
    assert [type(x) for x in result] == [type(x) for x in row]
    assert payload_hash(['one']) != payload_hash(['two'])


def test_reviewed_tables_require_explicit_opt_in_and_source_unchanged(tmp_path):
    path = fixture_backup(tmp_path, 'source.db')
    before = path.read_bytes()
    with pytest.raises(ValueError, match='preservation plan'):
        Backup(path)
    source = Backup(path, preserve_reviewed_legacy=True)
    try:
        metadata, rows, digest = legacy_snapshot(source, LEGACY)
        assert 'CREATE TABLE' in metadata
        assert decode_row(rows[0]) == (91, 456, 'private old name', b'\x00\xff')
        assert digest == payload_hash(rows)
        assert source.legacy_tables == [LEGACY] and LEGACY not in source.live_tables
    finally:
        source.close()
    assert path.read_bytes() == before


def test_archived_old_identity_is_not_merged_with_current_users(tmp_path):
    main = Backup(fixture_backup(tmp_path, 'main.db'), preserve_reviewed_legacy=True)
    medication = Backup(fixture_backup(tmp_path, 'med.db'), preserve_reviewed_legacy=True)
    try:
        assert audit(main, medication)['unlinked_medication_users'] == 0
        result = inspect_backup(main.path, preserve_reviewed_legacy=True)
        assert result['single_backup_schema_ready'] and not result['cutover_ready']
        assert result['reviewed_legacy_archive_tables'] == [LEGACY]
    finally:
        main.close(); medication.close()


def test_opt_in_still_rejects_unknown_tables(tmp_path):
    path = fixture_backup(tmp_path, 'source.db')
    with sqlite3.connect(path) as conn:
        conn.execute('CREATE TABLE unknown_private_data(id INTEGER)')
    with pytest.raises(ValueError, match='preservation plan'):
        Backup(path, preserve_reviewed_legacy=True)


def test_archive_does_not_execute_source_ddl_and_verifies_roundtrip(tmp_path, monkeypatch):
    source = Backup(fixture_backup(tmp_path, 'source.db'), preserve_reviewed_legacy=True)
    metadata, payloads, digest = legacy_snapshot(source, LEGACY)
    connection = MagicMock()
    copy_cursor = MagicMock()
    monkeypatch.setattr('psycopg.Cursor', MagicMock(return_value=copy_cursor))
    statements = []
    def execute(query, params=None):
        statement = query if isinstance(query, str) else query.as_string()
        statements.append(statement)
        response = MagicMock()
        if 'SELECT table_name' in statement:
            response.fetchall.return_value = []
        elif 'SELECT payload' in statement:
            response.fetchall.return_value = [(p,) for p in payloads]
        elif 'SELECT metadata' in statement:
            response.fetchone.return_value = (metadata, len(payloads), digest)
        return response
    connection.raw.execute.side_effect = execute
    try:
        assert write_legacy_archive(connection, source, 'alkong_main') == {LEGACY: 1}
        assert not any(LEGACY in sql for sql in statements)
        connection.commit.assert_not_called()  # caller owns the two-server transaction
        copy_cursor.__enter__.return_value.copy.assert_called_once()
    finally:
        source.close()


def test_archive_refuses_existing_destination(tmp_path):
    source = Backup(fixture_backup(tmp_path, 'source.db'), preserve_reviewed_legacy=True)
    connection = MagicMock()
    connection.raw.execute.return_value.fetchall.return_value = [('sqlite_tables',)]
    try:
        with pytest.raises(ValueError, match='already exists'):
            write_legacy_archive(connection, source, 'alkong_main')
        assert connection.raw.execute.call_count == 1
        connection.commit.assert_not_called()
    finally:
        source.close()


def test_archive_content_mismatch_stops_without_commit(tmp_path, monkeypatch):
    source = Backup(fixture_backup(tmp_path, 'source.db'), preserve_reviewed_legacy=True)
    connection = MagicMock()
    monkeypatch.setattr('psycopg.Cursor', MagicMock())
    connection.raw.execute.return_value.fetchall.return_value = []
    try:
        with pytest.raises(ValueError, match='verification failed'):
            write_legacy_archive(connection, source, 'alkong_main')
        connection.commit.assert_not_called()
    finally:
        source.close()


def test_views_are_not_silently_discarded(tmp_path):
    path = fixture_backup(tmp_path, 'source.db')
    with sqlite3.connect(path) as connection:
        connection.execute('CREATE VIEW private_view AS SELECT * FROM users')
    with pytest.raises(ValueError, match='views or active triggers'):
        Backup(path, preserve_reviewed_legacy=True)
