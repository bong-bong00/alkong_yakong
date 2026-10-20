import json

import pytest
from dotenv.main import dotenv_values

from scripts.prepare_render_cutover import prepare


@pytest.fixture
def config(tmp_path, monkeypatch):
    source = tmp_path / 'provider.json'
    source.write_text(json.dumps({
        'CLOVA_OCR_API_URL': 'https://example.invalid/ocr',
        'CLOVA_OCR_SECRET_KEY': 'synthetic-secret',
        'GEMINI_API_KEY': 'synthetic-gemini',
    }), encoding='utf-8')
    monkeypatch.setattr('dotenv.dotenv_values', lambda _: {
        'NEON_DATABASE_URL': 'postgresql://synthetic:synthetic@example.invalid/qa',
    })
    return source, tmp_path / 'private'


def test_roles_share_signing_key_but_not_authority_config(config):
    source, output = config
    result = prepare(source, output, 'https://qa-medication.onrender.com')
    main = dotenv_values(output / 'main.env')
    medication = dotenv_values(output / 'medication.env')
    assert main['ALKONGYAKONG_AUTH_SECRET'] == medication['ALKONGYAKONG_AUTH_SECRET']
    assert len(main['ALKONGYAKONG_AUTH_SECRET']) >= 32
    assert main['SERVICE_ROLE'] == 'main'
    assert medication['SERVICE_ROLE'] == 'medication'
    assert main['MEDICATION_FEATURE_BASE_URL'] == 'https://qa-medication.onrender.com'
    assert medication['AUTH_AUTHORITY_BASE_URL'] == 'https://alkong-yakong.onrender.com'
    assert medication['AUTH_ENFORCED'] == 'true'
    assert medication['DEMO_SEED_ENABLED'] == 'false'
    assert 'synthetic-secret' not in json.dumps(result)
    assert main['ALKONGYAKONG_AUTH_SECRET'] not in json.dumps(result)


def test_existing_signing_key_is_not_silently_replaced(config):
    source, output = config
    prepare(source, output, 'https://qa-medication.onrender.com')
    before = (output / 'shared-private.json').read_bytes()
    with pytest.raises(ValueError, match='will not be replaced'):
        prepare(source, output, 'https://qa-medication.onrender.com')
    assert (output / 'shared-private.json').read_bytes() == before


def test_non_render_destination_rejected(config):
    source, output = config
    with pytest.raises(ValueError, match='Render HTTPS'):
        prepare(source, output, 'http://example.invalid')
    assert not output.exists()
