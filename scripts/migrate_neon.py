"""Copy two verified SQLite backups into separate schemas of one PostgreSQL DB.

Default: local read-only audit, NO network. --apply requires --confirm-backups,
matching user IDs, and an EMPTY destination. Existing destinations are never
overwritten. Both imports and their hashes are verified in ONE transaction.
"""
from __future__ import annotations
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from dotenv import load_dotenv
load_dotenv(ROOT / ".env")


class Backup:
    def __init__(self, path, *, preserve_reviewed_legacy=False):
        path = Path(path).resolve(strict=True)
        if path == (ROOT / "alkongyakong.db").resolve():
            raise ValueError("Use verified OPERATING backups, not the repository demo database")
        self.path = path
        self.connection = sqlite3.connect(":memory:")
        # backup() gives a consistent snapshot and includes committed WAL data.
        try:
            with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)) as source:
                source.backup(self.connection)
            if self.connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise ValueError("A source backup has failed its integrity check")
            if self.connection.execute("PRAGMA foreign_key_check").fetchone() is not None:
                raise ValueError("A source backup has foreign-key errors; repair a copy first")
            self.tables = [row[0] for row in self.connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )]
            from init_db import TABLE_DEFINITIONS
            from scripts.legacy_archive import REVIEWED_LEGACY_TABLES
            extras = set(self.tables) - set(TABLE_DEFINITIONS)
            if extras and (not preserve_reviewed_legacy or extras - REVIEWED_LEGACY_TABLES):
                raise ValueError("Unrecognized source tables require an explicit preservation plan")
            self.legacy_tables = sorted(extras)
            self.live_tables = sorted(set(self.tables) & set(TABLE_DEFINITIONS))
            schema_objects = self.connection.execute(
                "SELECT type,tbl_name FROM sqlite_master WHERE type IN ('view','trigger')"
            ).fetchall()
            if any(kind == 'view' or owner not in self.legacy_tables for kind, owner in schema_objects):
                raise ValueError('Source views or active triggers require an explicit preservation plan')
            if "users" not in self.tables:
                raise ValueError("The backup does not contain the application account table")
        except Exception:
            self.connection.close()
            raise

    def columns(self, table):
        return [row[1] for row in self.connection.execute(f'PRAGMA table_info("{table}")')]

    def rows(self, table, columns):
        quoted = ",".join('"' + name.replace('"', '""') + '"' for name in columns)
        return self.connection.execute(f'SELECT {quoted} FROM "{table}" ORDER BY rowid').fetchall()

    def close(self):
        self.connection.close()


def row_hash(rows, columns):
    # PostgreSQL uses TEXT for mixed legacy INTEGER/UUID registration revisions.
    def normalize(row):
        return [str(value) if name == "registration_revision" and value is not None
                else value.hex() if isinstance(value, bytes) else value
                for name, value in zip(columns, row)]
    encoded = [json.dumps(normalize(row), ensure_ascii=False, separators=(",", ":")) for row in rows]
    return hashlib.sha256("\n".join(sorted(encoded)).encode()).hexdigest()


def audit(main, medication):
    main_ids = {row[0] for row in main.connection.execute("SELECT id FROM users")}
    required = set()
    for table in medication.live_tables:
        if "user_id" in medication.columns(table):
            required.update(row[0] for row in medication.connection.execute(
                f'SELECT DISTINCT user_id FROM "{table}" WHERE user_id IS NOT NULL'
            ))
    return {"mode": "dry-run", "network_access": False,
            "unlinked_medication_users": len(required - main_ids),
            "archived_tables": {role: source.legacy_tables for role, source in (("main", main), ("medication", medication))},
            "source_counts": {
                role: {table: source.connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
                       for table in source.tables}
                for role, source in (("main", main), ("medication", medication))}}


def apply_import(main, medication, url):
    from psycopg import sql
    from app.postgres import Connection, prepare_schema, SCHEMAS
    from init_db import TABLE_DEFINITIONS
    from scripts.legacy_archive import write_legacy_archive
    if audit(main, medication)["unlinked_medication_users"]:
        raise ValueError("Medication users absent from main need identity reconciliation; no IDs were guessed")
    connection = Connection(url, SCHEMAS["main"])
    try:
        connection.execute("BEGIN IMMEDIATE")
        # Lock both schemas in fixed order against concurrent migrations.
        connection.raw.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", (SCHEMAS["medication"],))
        result = {}
        archives = {}
        for role, source in (("main", main), ("medication", medication)):
            schema = SCHEMAS[role]
            connection.set_schema(schema)
            # Reject any nonempty/unknown existing table BEFORE touching it.
            existing = connection.raw.execute(
                "SELECT table_name FROM information_schema.tables WHERE table_schema=%s AND table_type='BASE TABLE'",
                (schema,),
            ).fetchall()
            for (table,) in existing:
                if table not in TABLE_DEFINITIONS:
                    raise ValueError("Destination has unknown tables; no changes were committed")
                count = connection.raw.execute(sql.SQL("SELECT COUNT(*) FROM {}.{}").format(
                    sql.Identifier(schema), sql.Identifier(table))).fetchone()[0]
                if count:
                    raise ValueError("Destination is not empty; overwriting existing records is forbidden")
            prepare_schema(connection)
            role_counts = {}
            # Dependency order is the same as schema creation (parents first).
            for table in TABLE_DEFINITIONS:
                if table not in source.tables:
                    continue
                columns = source.columns(table)
                rows = source.rows(table, columns)
                target_columns = {row[0] for row in connection.raw.execute(
                    "SELECT column_name FROM information_schema.columns WHERE table_schema=%s AND table_name=%s",
                    (schema, table),
                ).fetchall()}
                if set(columns) - target_columns:
                    raise ValueError("Source columns require a reviewed schema change; no columns were discarded")
                identifiers = sql.SQL(",").join(sql.Identifier(name) for name in columns)
                copy = sql.SQL("COPY {}.{} ({}) FROM STDIN").format(
                    sql.Identifier(schema), sql.Identifier(table), identifiers)
                import psycopg
                with psycopg.Cursor(connection.raw) as cursor:
                    with cursor.copy(copy) as writer:
                        for row in rows:
                            writer.write_row(tuple(str(value) if name == 'registration_revision' and value is not None
                                                   else value for name, value in zip(columns, row)))
                copied = connection.raw.execute(sql.SQL("SELECT {} FROM {}.{}").format(
                    identifiers, sql.Identifier(schema), sql.Identifier(table))).fetchall()
                if len(copied) != len(rows) or row_hash(copied, columns) != row_hash(rows, columns):
                    raise ValueError("Copied records did not match their source; the transaction was rolled back")
                # Explicit IDs must advance every identity sequence before new writes.
                identities = connection.raw.execute(
                    "SELECT column_name FROM information_schema.columns WHERE table_schema=%s AND table_name=%s AND is_identity='YES'",
                    (schema, table),
                ).fetchall()
                for (column,) in identities:
                    maximum = connection.raw.execute(sql.SQL("SELECT MAX({}) FROM {}.{}").format(
                        sql.Identifier(column), sql.Identifier(schema), sql.Identifier(table))).fetchone()[0]
                    sequence = connection.raw.execute("SELECT pg_get_serial_sequence(%s,%s)",
                                                      (f'{schema}.{table}', column)).fetchone()[0]
                    connection.raw.execute("SELECT setval(%s,%s,%s)", (sequence, max(1, maximum or 1), maximum is not None))
                role_counts[table] = len(rows)
            result[role] = role_counts
            archives[role] = write_legacy_archive(connection, source, schema)
        connection.commit()
        return {"mode": "applied", "integrity": "verified", "source_counts": result, "archive_counts": archives}
    except Exception:
        try:
            connection.rollback()
        except Exception:
            pass  # Lost connection/commit acknowledgement requires operator verification.
        raise
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--main-backup", required=True)
    parser.add_argument("--medication-backup", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirm-backups", action="store_true")
    parser.add_argument("--preserve-reviewed-legacy", action="store_true",
                        help="Archive only the six reviewed 20260614222707 legacy tables, without merging them")
    args = parser.parse_args()
    if Path(args.main_backup).resolve() == Path(args.medication_backup).resolve():
        parser.error("Two separate operating backups are required")
    if args.apply and not args.confirm_backups:
        parser.error("--apply requires --confirm-backups; stop operating writes and retain both backups first")
    backups = []
    try:
        backups.append(Backup(args.main_backup, preserve_reviewed_legacy=args.preserve_reviewed_legacy))
        backups.append(Backup(args.medication_backup, preserve_reviewed_legacy=args.preserve_reviewed_legacy))
        result = apply_import(*backups, os.getenv("NEON_DATABASE_URL", "")) if args.apply else audit(*backups)
        print(json.dumps(result, ensure_ascii=False))
    except Exception as error:
        # PostgreSQL errors may contain credentials/medical data; never print them.
        if isinstance(error, (ValueError, FileNotFoundError)):
            print("Migration stopped: " + (str(error) if isinstance(error, ValueError) else "backup file missing"), file=sys.stderr)
        else:
            print("Migration stopped; verify destination state before retrying. No backups were removed.", file=sys.stderr)
        raise SystemExit(1) from None
    finally:
        for backup in backups:
            backup.close()


if __name__ == "__main__":
    main()
