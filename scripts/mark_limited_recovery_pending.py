"""Add recovery metadata only to the exact previously certified partial rows.

Used when a candidate made before the recovery marker was introduced has
already been copied. Stops if patient rows or schedules/logs have changed.
"""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from dotenv import load_dotenv
load_dotenv(ROOT / '.env')


def mark(main_backup, candidate):
    from scripts.migrate_neon_limited import check_manifest
    from scripts.migrate_neon import row_hash
    from app.postgres import Connection, SCHEMAS
    manifest = check_manifest(main_backup, candidate)
    with closing(sqlite3.connect(Path(candidate).resolve().as_uri() + '?mode=ro', uri=True)) as source:
        columns = [row[1] for row in source.execute('PRAGMA table_info(user_medicines)')
                   if row[1] != 'schedule_recovery_pending']
        names = ','.join('"' + name + '"' for name in columns)
        original = source.execute(f'SELECT {names} FROM user_medicines').fetchall()
    if len(original) != manifest['copied_rows']['user_medicines']:
        raise ValueError('Candidate count mismatch')
    with Connection(os.getenv('NEON_DATABASE_URL', ''), SCHEMAS['medication']) as target:
        target.execute('ALTER TABLE user_medicines ADD COLUMN IF NOT EXISTS schedule_recovery_pending INTEGER NOT NULL DEFAULT 0')
        if target.execute('SELECT COUNT(*) FROM medication_schedules').fetchone()[0] or target.execute('SELECT COUNT(*) FROM medication_logs').fetchone()[0]:
            raise ValueError('Schedule/log state changed; no metadata update was applied')
        stored = [tuple(row) for row in target.execute(f'SELECT {names} FROM user_medicines FOR UPDATE').fetchall()]
        if row_hash(stored, columns) != row_hash(original, columns):
            raise ValueError('Recovered rows changed; no metadata update was applied')
        target.execute('UPDATE user_medicines SET schedule_recovery_pending=1')
    return {'certified_recovered_rows_marked': len(original), 'schedules_created': 0, 'logs_created': 0}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--main-backup', required=True)
    parser.add_argument('--partial-candidate', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(mark(args.main_backup, args.partial_candidate)))
    except Exception as error:
        print('Recovery marker stopped (' + type(error).__name__ + '); no values printed.', file=sys.stderr)
        raise SystemExit(1) from None
