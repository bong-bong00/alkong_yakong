"""Read-only audit of a partial API export against a verified main snapshot.

Never rebuilds schedules/logs, imports to Neon, or calls an operating API.
Reports counts and field names only; raw health data stays in the source files.
"""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3

FILES = (
    'medicines.json', 'prescriptions.json', 'today-medicines.json',
    'medication-history-days.json', 'medication-calendar-marked.json',
    'schedule-days.json',
)


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def normalized(value):
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
            if isinstance(decoded, (dict, list)):
                return decoded
        except ValueError:
            pass
    return value


def audit(export, main_backup):
    export = Path(export).resolve(strict=True)
    main_backup = Path(main_backup).resolve(strict=True)
    summary = read_json(export / 'summary.json')
    entries = summary['found_users']
    ids = [entry['user_id'] for entry in entries]
    if len(set(ids)) != len(ids):
        raise ValueError('Duplicate exported users')
    for user_id in ids:
        if not isinstance(user_id, str) or not user_id or Path(user_id).name != user_id or user_id in {'.', '..'} or '\\' in user_id:
            raise ValueError('Invalid exported folder identity')
    with closing(sqlite3.connect(main_backup.as_uri() + '?mode=ro', uri=True)) as connection:
        connection.row_factory = sqlite3.Row
        if connection.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise ValueError('Main snapshot integrity failure')
        if connection.execute('PRAGMA foreign_key_check').fetchone() is not None:
            raise ValueError('Main snapshot foreign key failure')
        users = {row[0] for row in connection.execute('SELECT id FROM users')}
        prescriptions = {row['id']: dict(row) for row in connection.execute('SELECT * FROM prescriptions')}
        items = {row['id']: dict(row) for row in connection.execute('SELECT * FROM prescription_items')}

    counts = Counter()
    changes = {'prescriptions': Counter(), 'items': Counter()}
    seen_rx, seen_items = set(), set()
    unsupported_fields = {'prescriptions': set(), 'items': set()}
    for entry in entries:
        folder = (export / entry['user_id']).resolve(strict=True)
        if folder.parent != export:
            raise ValueError('Export folder escapes source directory')
        payloads = {}
        for name in FILES:
            file = folder / name
            if file.resolve(strict=True).parent != folder:
                raise ValueError('Export file escapes user directory')
            payloads[name] = read_json(file)
            counts['json_files_checked'] += 1
        for key in ('medicines_status', 'prescription_status', 'today_status'):
            counts['reported_http_failures'] += entry.get(key) != 200
        counts['reported_history_errors'] += len(entry.get('history_error') or [])
        medicines = payloads['medicines.json']
        if not isinstance(medicines, dict) or not isinstance(medicines.get('medicines'), list):
            raise ValueError('Unexpected medicine envelope')
        counts['registered_medicines'] += len(medicines['medicines'])
        for name in FILES[3:]:
            if not isinstance(payloads[name], list):
                raise ValueError('Unexpected history/calendar/schedule envelope')
        counts['history_summary_days'] += len(payloads['medication-history-days.json'])
        rows = payloads['prescriptions.json']
        if not isinstance(rows, list):
            raise ValueError('Unexpected prescription envelope')
        for row in rows:
            identity = row.get('id')
            if not identity or identity in seen_rx:
                raise ValueError('Missing or duplicate prescription identity')
            seen_rx.add(identity)
            counts['prescriptions'] += 1
            counts['ocr_text_nonempty'] += bool(row.get('ocr_text'))
            counts['images_available'] += bool(row.get('original_image_path'))
            if row.get('user_id') != entry['user_id']:
                raise ValueError('Prescription export owner mismatch')
            old = prescriptions.get(identity)
            counts['prescriptions_in_main'] += old is not None
            if old and old.get('user_id') != row.get('user_id'):
                raise ValueError('Prescription main owner mismatch')
            if old:
                differences = [key for key, value in row.items() if key in old and normalized(value) != normalized(old[key])]
                counts['changed_prescriptions'] += bool(differences)
                changes['prescriptions'].update(differences)
                unsupported_fields['prescriptions'].update(set(row) - set(old) - {'items'})
            for item in row.get('items') or []:
                item_id = item.get('id')
                if not item_id or item_id in seen_items:
                    raise ValueError('Missing or duplicate prescription item identity')
                if item.get('prescription_id') != identity:
                    raise ValueError('Prescription item owner mismatch')
                seen_items.add(item_id)
                counts['items'] += 1
                counts['items_without_medicine_code'] += not bool(item.get('medicine_code'))
                old_item = items.get(item_id)
                counts['items_in_main'] += old_item is not None
                if old_item and old_item.get('prescription_id') != identity:
                    raise ValueError('Main prescription item owner mismatch')
                if old_item:
                    differences = [key for key, value in item.items() if key in old_item and normalized(value) != normalized(old_item[key])]
                    counts['changed_items'] += bool(differences)
                    changes['items'].update(differences)
                    unsupported_fields['items'].update(set(item) - set(old_item))
    return {
        'source_kind': 'partial_api_export_not_sqlite_backup',
        'network_access': False, 'operating_data_modified': False,
        'full_medication_migration_ready': False,
        'main_backup_sha256': hashlib.sha256(main_backup.read_bytes()).hexdigest(),
        'main_users': len(users), 'exported_users': len(ids),
        'export_users_not_in_main': len(set(ids) - users),
        'main_users_not_in_export': len(users - set(ids)),
        'main_prescriptions': len(prescriptions), 'main_items': len(items),
        'counts': dict(counts),
        'changed_fields': {key: dict(value) for key, value in changes.items()},
        'api_only_fields': {key: sorted(value) for key, value in unsupported_fields.items()},
        'unavailable_originals': [
            'all_operating_users', 'per_medicine_schedule_rows', 'medication_log_rows',
            'prescription_images', 'complete_medication_server_schema',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', required=True)
    parser.add_argument('--main-backup', required=True)
    args = parser.parse_args()
    try:
        result = audit(args.export, args.main_backup)
    except (ValueError, KeyError, TypeError, OSError, sqlite3.Error):
        parser.exit(1, 'Audit rejected malformed/incomplete source; no data was changed.\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
