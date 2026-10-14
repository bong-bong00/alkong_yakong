"""Run the deployed OCR engine on an explicitly supplied private test image.

Does not initialize or write an application DB. Output contains prescription
data and MUST be outside Git; stdout is aggregate/redacted only.
"""
import argparse
from dataclasses import asdict
import json
import os
from pathlib import Path
import sys
import time

ROOT = Path(os.getenv('ALKONG_QA_PROJECT_ROOT', str(Path(__file__).resolve().parents[1]))).resolve()
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    output = Path(args.output).resolve()
    if output.is_relative_to(ROOT):
        raise SystemExit('Private OCR output must be outside the repository')
    from app.services.ocr.engine import extract_raw_text
    started = time.monotonic()
    result = extract_raw_text(Path(args.image).read_bytes())
    payload = asdict(result)
    payload['error'] = str(result.error).split(':', 1)[0] if result.error else None
    payload['elapsed_seconds'] = round(time.monotonic() - started, 2)
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as stream:
        json.dump(payload, stream, ensure_ascii=False)
    print(json.dumps({'ok': result.ok, 'engine': result.engine_name,
        'field_count': len(result.fields), 'table_count': len(result.tables),
        'confidence': result.confidence, 'elapsed_seconds': payload['elapsed_seconds'],
        'error_code': payload['error']}))
    return 0 if result.ok else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('Live OCR QA failed (' + type(error).__name__ + ')', file=sys.stderr)
        raise SystemExit(1) from None
