"""Build an explicitly PARTIAL medication recovery candidate, offline only.

Uses exported current medicine identities and verified main prescription rows.
Never invents schedule rows or taken_at logs. Not a j0jn SQLite backup.
"""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from init_db import TABLE_DEFINITIONS
from scripts.audit_j0jn_api_export import audit, normalized, read_json


def prepare(export, main_backup, output):
    export, main_backup = Path(export).resolve(strict=True), Path(main_backup).resolve(strict=True)
    output = Path(output).resolve()
    if output.is_relative_to(ROOT) or output.exists() or output == main_backup:
        raise ValueError('Use a new output outside the repository')
    result = audit(export, main_backup)
    counts = result['counts']
    if result['export_users_not_in_main'] or counts.get('reported_http_failures') or counts.get('reported_history_errors'):
        raise ValueError('Export is incomplete even within its declared scope')
    if counts['changed_prescriptions'] or counts['changed_items'] or counts['prescriptions'] != counts['prescriptions_in_main'] or counts['items'] != counts['items_in_main']:
        raise ValueError('Prescription reconciliation required')
    selected_rx, selected_items, current = set(), set(), []
    for entry in read_json(export / 'summary.json')['found_users']:
        folder = export / entry['user_id']
        for rx in read_json(folder / 'prescriptions.json'):
            selected_rx.add(rx['id'])
            selected_items.update(item['id'] for item in rx.get('items') or [])
        for medicine in read_json(folder / 'medicines.json')['medicines']:
            current.append((entry['user_id'], medicine))
    identities = [medicine.get('user_medicine_id') for _, medicine in current]
    if any(not isinstance(identity, int) or isinstance(identity, bool) for identity in identities) or len(set(identities)) != len(identities):
        raise ValueError('Missing or duplicate current medicine identity')
    with closing(sqlite3.connect(main_backup.as_uri() + '?mode=ro', uri=True)) as source:
        source.row_factory = sqlite3.Row
        recovered = []
        for owner, medicine in current:
            row = source.execute('SELECT * FROM user_medicines WHERE id=?', (medicine['user_medicine_id'],)).fetchone()
            if row is None or row['user_id'] != owner or row['medicine_code'] != medicine.get('medicine_code'):
                raise ValueError('Current medicine identity/owner mismatch')
            row = dict(row)
            # API current-list values take precedence only for these real fields.
            for key in ('dosage', 'dose_amount', 'dose_unit', 'frequency_per_day', 'administration_times', 'last_prescribed_at'):
                if key in medicine:
                    value = medicine[key]
                    row[key] = json.dumps(value, ensure_ascii=False) if isinstance(value, (dict, list)) else value
            status = str(medicine.get('status') or '').upper()
            if status not in {'ACTIVE', 'PAST'}:
                raise ValueError('Unreviewed API medicine status')
            row['status'] = status
            row['is_active'] = int(status == 'ACTIVE')
            # j0jn export does not expose original course dates. A main-server
            # date must not silently hide an API-confirmed current medicine.
            row['start_date'] = None
            row['end_date'] = None
            if medicine.get('registered_at'):
                row['created_at'] = medicine['registered_at']
            if row.get('prescription_item_id') not in selected_items:
                row['prescription_item_id'] = None
            recovered.append(row)
        selections = {
            'users': [dict(row) for row in source.execute('SELECT * FROM users')],
            'medicines': [dict(row) for row in source.execute('SELECT * FROM medicines')],
            'dur_taboo': [dict(row) for row in source.execute('SELECT * FROM dur_taboo')],
            'prescriptions': [dict(row) for row in source.execute('SELECT * FROM prescriptions') if row['id'] in selected_rx],
            'prescription_items': [dict(row) for row in source.execute('SELECT * FROM prescription_items') if row['id'] in selected_items],
            'user_medicines': recovered,
        }
    # Exclusive creation: never overwrite an earlier recovery candidate.
    with output.open('xb'):
        pass
    with closing(sqlite3.connect(output)) as destination:
        destination.execute('PRAGMA foreign_keys=ON')
        with destination:
            for table, definition in TABLE_DEFINITIONS.items():
                destination.execute(definition)
                for row in selections.get(table, []):
                    available = {entry[1] for entry in destination.execute(f'PRAGMA table_info("{table}")')}
                    if set(row) - available:
                        raise ValueError('Source fields would be discarded')
                    columns = ','.join('"' + key + '"' for key in row)
                    placeholders = ','.join('?' for _ in row)
                    destination.execute(f'INSERT INTO "{table}" ({columns}) VALUES ({placeholders})', tuple(row.values()))
            if destination.execute('PRAGMA foreign_key_check').fetchone() is not None:
                raise ValueError('Recovery candidate foreign key failure')
        if destination.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise ValueError('Recovery candidate integrity failure')
    result = {
        'source_kind': 'user_approved_partial_recovery_not_j0jn_backup',
        'network_access': False, 'operating_data_modified': False,
        'main_backup_sha256': result['main_backup_sha256'],
        'candidate_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
        'copied_rows': {table: len(rows) for table, rows in selections.items()},
        'medication_schedules': 0, 'medication_logs': 0,
        'active_medicines': sum(row['is_active'] for row in recovered),
        'past_medicines': sum(not row['is_active'] for row in recovered),
        'course_dates': 'unknown; not inferred from main or API summaries',
        'limitation': 'No original j0jn schedules/logs/images or complete user coverage. Main records remain in main schema/source backup.',
    }
    manifest = output.with_suffix(output.suffix + '.manifest.json')
    with manifest.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', required=True)
    parser.add_argument('--main-backup', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.export, args.main_backup, args.output), ensure_ascii=False, indent=2))
    except Exception:
        parser.exit(1, 'Preparation stopped. Any output is an unverified candidate; do not import it. Sources unchanged.\n')
