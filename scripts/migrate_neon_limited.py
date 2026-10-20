"""Separate, explicit partial-recovery path. Does not weaken full-backup import.

Default offline dry run. Applying still requires write suspension, confirmation,
an empty destination, and the original main backup plus a certified candidate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.migrate_neon import Backup, audit, apply_import


def check_manifest(main_path, candidate_path):
    main_path, candidate_path = Path(main_path), Path(candidate_path)
    manifest = json.loads(candidate_path.with_suffix(candidate_path.suffix + '.manifest.json').read_text(encoding='utf-8'))
    if manifest.get('source_kind') != 'user_approved_partial_recovery_not_j0jn_backup':
        raise ValueError('Not a certified partial recovery candidate')
    for key, path in [('main_backup_sha256', main_path), ('candidate_sha256', candidate_path)]:
        if hashlib.sha256(path.read_bytes()).hexdigest() != manifest.get(key):
            raise ValueError('Recovery certificate hash mismatch')
    return manifest


def inspect(main, medication, manifest):
    result = audit(main, medication)
    if result['unlinked_medication_users']:
        raise ValueError('User reconciliation required')
    counts = result['source_counts']['medication']
    if any(counts.get(table) != count for table, count in manifest['copied_rows'].items()):
        raise ValueError('Candidate row counts differ from certificate')
    if counts.get('medication_logs') or counts.get('medication_schedules'):
        raise ValueError('Candidate must not contain reconstructed schedules/logs')
    result.update(source_kind=manifest['source_kind'], full_j0jn_restore=False,
                  active_medicines=manifest['active_medicines'],
                  past_medicines=manifest['past_medicines'],
                  limitations=manifest['limitation'], course_dates=manifest['course_dates'])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--main-backup', required=True)
    parser.add_argument('--partial-candidate', required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--confirm-partial-recovery', action='store_true')
    parser.add_argument('--confirm-writes-suspended', action='store_true')
    args = parser.parse_args()
    if args.apply and not (args.confirm_partial_recovery and args.confirm_writes_suspended):
        parser.error('Apply requires explicit partial-recovery and write-suspension confirmation')
    sources = []
    try:
        manifest = check_manifest(args.main_backup, args.partial_candidate)
        sources = [Backup(args.main_backup, preserve_reviewed_legacy=True)]
        sources.append(Backup(args.partial_candidate))
        result = inspect(*sources, manifest)
        if args.apply:
            applied = apply_import(*sources, os.getenv('NEON_DATABASE_URL', ''))
            result.update(applied)
            result['network_access'] = True
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except Exception:
        parser.exit(1, 'Limited migration stopped; verify inputs/destination before retrying. No source was changed.\n')
    finally:
        for source in sources:
            source.close()


if __name__ == '__main__':
    main()
