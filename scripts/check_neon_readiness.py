"""Read-only Neon connectivity/schema check; never initialize application tables."""
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def inspect_connection(url):
    import certifi
    import psycopg
    from app.postgres import validate_url
    validate_url(url)
    if not urlsplit(url).hostname.endswith('.neon.tech'):
        raise ValueError('Expected a Neon connection URL')
    schemas = ['alkong_main', 'alkong_medication', 'alkong_main_archive', 'alkong_medication_archive']
    with psycopg.connect(url, sslmode='verify-full', sslrootcert=certifi.where(), connect_timeout=15) as connection:
        connection.execute('SET TRANSACTION READ ONLY')
        connection.execute("SET LOCAL statement_timeout='10s'")
        version = connection.execute('SHOW server_version').fetchone()[0]
        read_only = connection.execute('SHOW transaction_read_only').fetchone()[0] == 'on'
        rows = connection.execute("SELECT table_schema,COUNT(*) FROM information_schema.tables "
            "WHERE table_schema=ANY(%s) AND table_type='BASE TABLE' GROUP BY table_schema", (schemas,)).fetchall()
    return {'connection_verified': True, 'transaction_read_only': read_only,
            'server_version': version, 'schema_table_counts': {s: dict(rows).get(s, 0) for s in schemas},
            'changes_made': False, 'migration_completed': False}


def main():
    from dotenv import load_dotenv
    load_dotenv(ROOT / '.env')
    try:
        print(json.dumps(inspect_connection(os.getenv('NEON_DATABASE_URL', '')), ensure_ascii=False))
    except Exception as error:
        print('Neon read-only check failed (' + type(error).__name__ + ')', file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == '__main__':
    main()
