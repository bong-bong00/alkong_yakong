"""Real PostgreSQL rehearsal using synthetic data in disposable schemas only.

NEON_DATABASE_URL is used without printing it. No operating backup is uploaded,
and neither application schema is written. Only our random test schemas are
removed after testing, including the synthetic legacy archive.
"""
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from dotenv import load_dotenv
load_dotenv(ROOT / '.env')


def run():
    from psycopg import sql
    from app.postgres import Connection, SCHEMAS
    from init_db import TABLE_DEFINITIONS
    from scripts.migrate_neon import Backup, apply_import
    from scripts.legacy_archive import REVIEWED_LEGACY_TABLES
    url = os.getenv('NEON_DATABASE_URL', '')
    schemas = {role: 'alkong_test_' + uuid.uuid4().hex for role in ('main', 'medication')}
    cleanup = set(schemas.values()) | {schema + '_archive' for schema in schemas.values()}
    original = dict(SCHEMAS)
    result = {'synthetic_data_only': True, 'operating_schemas_untouched': True}
    with tempfile.TemporaryDirectory(prefix='alkong-neon-synthetic-') as directory, patch.dict(SCHEMAS, schemas):
        sources = []
        connection = None
        try:
            for role in ('main', 'medication'):
                path = Path(directory) / (role + '.db')
                with closing(sqlite3.connect(path)) as local:
                    with local:
                        for definition in TABLE_DEFINITIONS.values():
                            local.execute(definition)
                        local.execute("INSERT INTO users(id,name,role) VALUES('qa-user','Synthetic QA','PATIENT')")
                        local.execute("INSERT INTO medicines(medicine_code,product_name,ingredient) VALUES('QA','Synthetic drug','Synthetic ingredient')")
                        local.execute("INSERT INTO prescriptions(id,user_id,registration_revision) VALUES('same-id','qa-user','synthetic-uuid')")
                        local.execute("INSERT INTO prescription_items(id,prescription_id,medicine_code,ocr_drug_name) VALUES(9,'same-id','QA','Synthetic OCR')")
                        if role == 'main':
                            for table in REVIEWED_LEGACY_TABLES:
                                local.execute(f'CREATE TABLE "{table}" (value)')
                                local.executemany(f'INSERT INTO "{table}" VALUES (?)', [(None,), (1,), (1.25,), ('Synthetic',), (b'bytes',)])
                sources.append(Backup(path, preserve_reviewed_legacy=True))
            applied = apply_import(*sources, url)
            result['copy_hashes_verified'] = applied['integrity'] == 'verified'
            result['legacy_rows_verified'] = sum(applied['archive_counts']['main'].values())
            try:
                apply_import(*sources, url)
            except ValueError:
                result['nonempty_destination_rejected'] = True
            else:
                raise AssertionError('Nonempty destination unexpectedly accepted')
            connection = Connection(url, schemas['medication'])
            cursor = connection.execute("INSERT INTO prescription_items(prescription_id,medicine_code,ocr_drug_name) VALUES('same-id','QA','Synthetic new item')")
            result['identity_sequence_advanced'] = cursor.lastrowid > 9
            try:
                connection.execute("INSERT INTO prescriptions(id,user_id) VALUES('orphan','missing-user')")
            except sqlite3.IntegrityError:
                result['foreign_key_enforced'] = True
            else:
                raise AssertionError('Foreign key unexpectedly accepted')
            result['connection_recovers_after_constraint_error'] = connection.execute('SELECT COUNT(*) FROM prescriptions').fetchone()[0] == 1
            connection.rollback()
            for schema in schemas.values():
                connection.set_schema(schema)
                assert connection.execute('SELECT registration_revision FROM prescriptions').fetchone()[0] == 'synthetic-uuid'
            result['colliding_ids_isolated'] = True
        finally:
            for source in sources:
                source.close()
            if connection is not None:
                connection.close()
            for schema in cleanup:
                assert schema not in original.values() and schema.startswith('alkong_test_')
            with Connection(url, schemas['main']) as cleaner:
                for schema in sorted(cleanup):
                    cleaner.raw.execute(sql.SQL('DROP SCHEMA IF EXISTS {} CASCADE').format(sql.Identifier(schema)))
            result['disposable_schemas_removed'] = True
    return result


if __name__ == '__main__':
    try:
        print(json.dumps(run(), ensure_ascii=False, indent=2))
    except Exception as error:
        print('Synthetic Neon rehearsal failed (' + type(error).__name__ + '); verify cleanup before retry.', file=sys.stderr)
        raise SystemExit(1) from None
