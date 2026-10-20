"""Prepare private Render environment files without printing their contents.

Reads only an approved provider-key export and the local Neon URL. Output must
be new and outside Git. File upload is done through Render's own UI, not an API
or browser cookie extraction. Credentials never belong in stdout or Git.
"""
import argparse
import json
import secrets
import sys
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

PROVIDER_KEYS = {
    'E_DRUG_API_KEY', 'MFDS_SERVICE_KEY', 'DUR_API_KEY',
    'MFDS_DRUG_PERMISSION_API_KEY', 'CLOVA_OCR_API_URL',
    'CLOVA_OCR_SECRET_KEY', 'CLOVA_OCR_ENABLED', 'GEMINI_API_KEY', 'GEMINI_MODEL',
}


def prepare(provider_file, output_directory, medication_url):
    from dotenv import dotenv_values
    from app.postgres import validate_url
    directory = Path(output_directory).resolve()
    if directory.is_relative_to(ROOT):
        raise ValueError('Private configuration must remain outside Git')
    files = [directory / name for name in ('main.env', 'medication.env', 'shared-private.json')]
    if any(file.exists() for file in files):
        raise ValueError('Existing cutover credentials will not be replaced')
    if urlsplit(medication_url).scheme != 'https' or not urlsplit(medication_url).hostname.endswith('.onrender.com'):
        raise ValueError('Expected approved Render HTTPS URL')
    providers = json.loads(Path(provider_file).read_text(encoding='utf-8'))
    if set(providers) - PROVIDER_KEYS:
        raise ValueError('Unexpected exported configuration')
    if not providers.get('CLOVA_OCR_API_URL') or not providers.get('CLOVA_OCR_SECRET_KEY') or not providers.get('GEMINI_API_KEY'):
        raise ValueError('Approved API configuration is incomplete')
    neon = dotenv_values(ROOT / '.env').get('NEON_DATABASE_URL', '')
    validate_url(neon)
    shared = {
        'NEON_DATABASE_URL': neon,
        'ALKONGYAKONG_AUTH_SECRET': secrets.token_urlsafe(48),
        'ALKONGYAKONG_DATABASE_BACKEND': 'postgresql',
        'AUTH_ENFORCED': 'true', 'APP_ENV': 'production',
        'DEMO_SEED_ENABLED': 'false', 'PRESENTATION_SEED_ENABLED': 'false',
        'DUR_AUTO_SYNC': 'false',
        **providers,
    }
    directory.mkdir(parents=True, exist_ok=True)
    for role, file in zip(('main', 'medication'), files):
        data = dict(shared, SERVICE_ROLE=role)
        if role == 'main':
            data['MEDICATION_FEATURE_BASE_URL'] = medication_url
        else:
            data['AUTH_AUTHORITY_BASE_URL'] = 'https://alkong-yakong.onrender.com'
        with file.open('x', encoding='utf-8', newline='\n') as stream:
            for key, value in data.items():
                # JSON quoting safely preserves newlines and special characters
                # in the dotenv parser used by Render and by local verification.
                stream.write(key + '=' + json.dumps(str(value), ensure_ascii=False) + '\n')
        file.chmod(0o600)
    with files[2].open('x', encoding='utf-8') as stream:
        json.dump(shared, stream, ensure_ascii=False)
    files[2].chmod(0o600)
    return {'private_files_created': len(files), 'provider_keys_present': sorted(providers),
            'credentials_printed': False, 'render_settings_changed': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--provider-file', required=True)
    parser.add_argument('--output-directory', required=True)
    parser.add_argument('--medication-url', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.provider_file, args.output_directory, args.medication_url)))
    except Exception as error:
        print('Private configuration preparation failed (' + type(error).__name__ + '); no secrets printed.', file=sys.stderr)
        raise SystemExit(1) from None
