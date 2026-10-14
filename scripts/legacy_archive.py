"""Lossless archive of explicitly reviewed legacy tables, never executed as SQL."""
import base64
import hashlib
import json

REVIEWED_LEGACY_TABLES = frozenset(
    'legacy_' + name + '_20260614222707'
    for name in ('users', 'guardians', 'prescriptions', 'prescription_drugs',
                 'medication_schedules', 'medication_logs')
)


def encode_row(row):
    def value(item):
        if item is None:
            return ['null', None]
        if isinstance(item, bytes):
            return ['blob', base64.b64encode(item).decode('ascii')]
        if isinstance(item, int):
            return ['integer', str(item)]
        if isinstance(item, float):
            return ['real', item.hex()]
        if isinstance(item, str):
            return ['text', item]
        raise ValueError('Unsupported legacy SQLite storage type')
    return json.dumps([value(item) for item in row], ensure_ascii=False, separators=(',', ':'))


def decode_row(payload):
    decoders = {'null': lambda _: None, 'blob': base64.b64decode, 'integer': int,
                'real': float.fromhex, 'text': lambda item: item}
    return tuple(decoders[kind](item) for kind, item in json.loads(payload))


def payload_hash(payloads):
    digest = hashlib.sha256()
    for payload in payloads:
        digest.update(payload.encode('utf-8'))
        digest.update(b'\n')
    return digest.hexdigest()


def legacy_snapshot(source, table):
    if table not in REVIEWED_LEGACY_TABLES:
        raise ValueError('Legacy table has not been reviewed')
    columns = source.columns(table)
    rows = source.rows(table, columns)
    payloads = [encode_row(row) for row in rows]
    if [decode_row(payload) for payload in payloads] != rows:
        raise ValueError('Legacy encoding verification failed')
    # Preserve DDL/index/trigger definitions as inert text. Do not execute source SQL.
    objects = source.connection.execute(
        'SELECT type,name,sql FROM sqlite_master WHERE tbl_name=? ORDER BY type,name', (table,)
    ).fetchall()
    metadata = json.dumps({'columns': columns, 'objects': objects}, ensure_ascii=False, separators=(',', ':'))
    return metadata, payloads, payload_hash(payloads)


def write_legacy_archive(connection, source, app_schema):
    from psycopg import sql
    from app.postgres import SCHEMAS
    if app_schema not in SCHEMAS.values():
        raise ValueError('Unsupported archive owner')
    if not source.legacy_tables:
        return {}
    schema = app_schema + '_archive'
    existing = connection.raw.execute(
        'SELECT table_name FROM information_schema.tables WHERE table_schema=%s', (schema,)
    ).fetchall()
    if existing:
        raise ValueError('Destination legacy archive already exists; no overwrite is allowed')
    connection.raw.execute(sql.SQL('CREATE SCHEMA IF NOT EXISTS {}').format(sql.Identifier(schema)))
    connection.raw.execute(sql.SQL('CREATE TABLE {}.sqlite_tables (table_name TEXT PRIMARY KEY, '
        'metadata TEXT NOT NULL, row_count BIGINT NOT NULL, content_sha256 TEXT NOT NULL)').format(sql.Identifier(schema)))
    connection.raw.execute(sql.SQL('CREATE TABLE {}.sqlite_rows (table_name TEXT NOT NULL REFERENCES '
        '{}.sqlite_tables(table_name), ordinal BIGINT NOT NULL, payload TEXT NOT NULL, '
        'PRIMARY KEY(table_name,ordinal))').format(sql.Identifier(schema), sql.Identifier(schema)))
    counts = {}
    for table in source.legacy_tables:
        metadata, payloads, digest = legacy_snapshot(source, table)
        connection.raw.execute(sql.SQL('INSERT INTO {}.sqlite_tables VALUES(%s,%s,%s,%s)').format(sql.Identifier(schema)),
                               (table, metadata, len(payloads), digest))
        # Regular Cursor, not ClientCursor: COPY uses the PostgreSQL copy protocol.
        import psycopg
        with psycopg.Cursor(connection.raw) as cursor:
            with cursor.copy(sql.SQL('COPY {}.sqlite_rows FROM STDIN').format(sql.Identifier(schema))) as writer:
                for ordinal, payload in enumerate(payloads):
                    writer.write_row((table, ordinal, payload))
        stored = connection.raw.execute(sql.SQL('SELECT payload FROM {}.sqlite_rows WHERE table_name=%s '
            'ORDER BY ordinal').format(sql.Identifier(schema)), (table,)).fetchall()
        actual = [r[0] for r in stored]
        stored_meta = connection.raw.execute(sql.SQL('SELECT metadata,row_count,content_sha256 FROM '
            '{}.sqlite_tables WHERE table_name=%s').format(sql.Identifier(schema)), (table,)).fetchone()
        if actual != payloads or payload_hash(actual) != digest or stored_meta != (metadata, len(payloads), digest):
            raise ValueError('Legacy archive verification failed; no changes will be committed')
        counts[table] = len(payloads)
    return counts
