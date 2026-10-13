"""Validate the additive rollout on a SQLite backup before touching the source.

Dry-run is the default. --apply requires a new backup path and a maintenance
window with application writes stopped. No patient data is printed.
"""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import init_db

PROTECTED = (
    "users", "prescriptions", "prescription_items", "user_medicines",
    "medication_schedules", "medication_logs", "heart_rate_logs",
    "baseline_heart_rate", "abnormal_events", "guardians",
)


def readonly(path):
    resolved = Path(path).resolve(strict=True)
    return sqlite3.connect(resolved.as_uri() + "?mode=ro", uri=True)


def verify(conn):
    if conn.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        raise RuntimeError("Database integrity check failed")
    if conn.execute("PRAGMA foreign_key_check").fetchone() is not None:
        raise RuntimeError("Existing foreign-key errors need review before migration")


def snapshot(conn, columns=None):
    result = {}
    for table in PROTECTED:
        info = conn.execute(f'PRAGMA table_info("{table}")').fetchall()
        if not info:
            continue
        if columns is not None and table not in columns:
            continue
        fields = columns[table] if columns is not None else [row[1] for row in info]
        # Consent migration intentionally changes these two metadata fields.
        fields = [name for name in fields if table != "guardians" or name not in {"status", "consent_verified_at"}]
        select = ",".join('"' + name.replace('"', '""') + '"' for name in fields)
        rows = conn.execute(f'SELECT {select} FROM "{table}" ORDER BY rowid').fetchall()
        encoded = json.dumps(rows, ensure_ascii=False, default=str, separators=(",", ":")).encode()
        result[table] = {"columns": fields, "count": len(rows), "hash": hashlib.sha256(encoded).hexdigest()}
    return result


def migrate(path):
    original = init_db.DB_PATH
    try:
        init_db.DB_PATH = str(path)
        init_db.initialize_database(preserve_records=True)
    finally:
        init_db.DB_PATH = original


def backup(source, destination):
    destination = Path(destination).resolve()
    if destination.exists():
        raise FileExistsError("Backup already exists; it will not be overwritten")
    if not destination.parent.is_dir():
        raise FileNotFoundError("Backup directory must already exist")
    with closing(readonly(source)) as src, closing(sqlite3.connect(destination)) as dst:
        verify(src)
        src.backup(dst)
        verify(dst)


def prepare(source, *, apply=False, backup_path=None):
    source = Path(source).resolve(strict=True)
    with closing(readonly(source)) as conn:
        verify(conn)
        before = snapshot(conn)
    fields = {table: row["columns"] for table, row in before.items()}
    with tempfile.TemporaryDirectory(prefix="alkong-migration-") as directory:
        trial = Path(directory) / "trial.db"
        backup(source, trial)
        for _ in range(2):
            migrate(trial)
            with closing(readonly(trial)) as conn:
                verify(conn)
                after = snapshot(conn, fields)
            # Newly created empty tables are allowed; all original rows remain.
            if any(after.get(table) != values for table, values in before.items()):
                raise RuntimeError("Migration changed a protected existing record")
    if apply:
        if not backup_path:
            raise ValueError("--apply requires --backup")
        backup(source, backup_path)
        migrate(source)
        with closing(readonly(source)) as conn:
            verify(conn)
            after = snapshot(conn, fields)
        if any(after.get(table) != values for table, values in before.items()):
            raise RuntimeError("Post-apply verification failed; retained backup needs operator review")
    return {"mode": "applied" if apply else "dry-run", "integrity": "ok",
            "migration_runs_verified": 2, "counts": {table: row["count"] for table, row in before.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--backup")
    args = parser.parse_args()
    print(json.dumps(prepare(args.database, apply=args.apply, backup_path=args.backup), ensure_ascii=False))


if __name__ == "__main__":
    main()
