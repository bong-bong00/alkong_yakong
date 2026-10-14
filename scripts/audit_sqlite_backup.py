"""Read-only readiness audit for ONE operating SQLite snapshot; no network."""
from contextlib import closing
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from init_db import TABLE_DEFINITIONS


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def inspect_backup(path, *, preserve_reviewed_legacy=False):
    path = Path(path).resolve(strict=True)
    if path == (ROOT / 'alkongyakong.db').resolve():
        raise ValueError('Use an operating backup, not the repository database')
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as source:
        with closing(sqlite3.connect(':memory:')) as snapshot:
            source.backup(snapshot)
            integrity = snapshot.execute('PRAGMA integrity_check').fetchone()[0]
            foreign_errors = len(snapshot.execute('PRAGMA foreign_key_check').fetchall())
            tables = [r[0] for r in snapshot.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )]
            counts = {t: snapshot.execute('SELECT COUNT(*) FROM ' + quote(t)).fetchone()[0] for t in tables}
            differences = {}
            unique_conflicts = []
            with closing(sqlite3.connect(':memory:')) as target:
                for definition in TABLE_DEFINITIONS.values():
                    target.execute(definition)
                for table in set(tables) & set(TABLE_DEFINITIONS):
                    actual = {r[1] for r in snapshot.execute('PRAGMA table_info(' + quote(table) + ')')}
                    expected = {r[1] for r in target.execute('PRAGMA table_info(' + quote(table) + ')')}
                    if actual != expected:
                        differences[table] = {'unknown_columns': sorted(actual - expected),
                                              'missing_columns': sorted(expected - actual)}
                    for index in target.execute('PRAGMA index_list(' + quote(table) + ')').fetchall():
                        if not index[2]:
                            continue
                        columns = [r[2] for r in target.execute('PRAGMA index_info(' + quote(index[1]) + ')')]
                        if not columns or not set(columns) <= actual:
                            continue
                        fields = ','.join(quote(c) for c in columns)
                        nonnull = ' AND '.join(quote(c) + ' IS NOT NULL' for c in columns)
                        groups = snapshot.execute('SELECT COUNT(*) FROM (SELECT ' + fields + ' FROM ' +
                            quote(table) + ' WHERE ' + nonnull + ' GROUP BY ' + fields + ' HAVING COUNT(*)>1)').fetchone()[0]
                        if groups:
                            unique_conflicts.append({'table': table, 'columns': columns, 'duplicate_groups': groups})
    after = hashlib.sha256(path.read_bytes()).hexdigest()
    unknown = sorted(set(tables) - set(TABLE_DEFINITIONS))
    from scripts.legacy_archive import REVIEWED_LEGACY_TABLES
    archived = sorted(set(unknown) & REVIEWED_LEGACY_TABLES) if preserve_reviewed_legacy else []
    unresolved = sorted(set(unknown) - set(archived))
    ready = integrity == 'ok' and not foreign_errors and not unresolved and not unique_conflicts and 'users' in tables
    ready = ready and not any(d['unknown_columns'] for d in differences.values()) and before == after
    return {'network_access': False, 'source_unchanged': before == after, 'sha256': after,
            'integrity': integrity, 'foreign_key_errors': foreign_errors, 'table_counts': counts,
            'tables_requiring_preservation_plan': unresolved, 'reviewed_legacy_archive_tables': archived,
            'schema_differences': differences,
            'unique_conflicts': unique_conflicts, 'single_backup_schema_ready': ready,
            'cutover_ready': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('backup')
    parser.add_argument('--preserve-reviewed-legacy', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(inspect_backup(args.backup, preserve_reviewed_legacy=args.preserve_reviewed_legacy), ensure_ascii=False, indent=2))
    except Exception as error:
        # Never disclose SQLite errors, row contents, credentials, or patient data.
        print('Backup audit failed (' + type(error).__name__ + ')', file=sys.stderr)
        raise SystemExit(1) from None
