"""원본 처방전 사진 위에 OCR 인식 글자(대략 위치)를 그려 저장한다.

사용:
  python tools/make_ocr_overlay.py 20260825_164345.jpg
  python tools/make_ocr_overlay.py 20260620_165936.jpg --out ocr_overlay.png
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.core.config import GEMINI_API_KEY, GEMINI_MODEL
from app.services.ocr.engine import _prepare_image


BOX_SCHEMA = {
    "type": "object",
    "properties": {
        "lines": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"},
                    "ymin": {"type": "integer"},
                    "xmin": {"type": "integer"},
                    "ymax": {"type": "integer"},
                    "xmax": {"type": "integer"},
                },
                "required": ["text", "ymin", "xmin", "ymax", "xmax"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["lines"],
    "additionalProperties": False,
}


def detect_text_boxes(image_bytes: bytes) -> list[dict]:
    if not GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY가 없습니다.")

    from google import genai
    from google.genai import types

    prepared, mime = _prepare_image(image_bytes)
    part = types.Part.from_bytes(data=prepared, mime_type=mime)
    prompt = (
        "이 사진은 한국 처방전/복약안내문입니다. "
        "보이는 글자 줄마다 텍스트와 위치 박스를 JSON으로 반환하세요. "
        "좌표는 이미지 기준 0~1000 정규화 정수 "
        "(ymin, xmin, ymax, xmax) 입니다. "
        "약품명·용량·횟수·일수·병원·날짜 줄을 우선하세요. "
        "추측하지 말고 보이는 글자만 넣으세요."
    )
    with genai.Client(api_key=GEMINI_API_KEY) as client:
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=[part, prompt],
            config={
                "temperature": 0.0,
                "response_mime_type": "application/json",
                "response_json_schema": BOX_SCHEMA,
            },
        )
    parsed = getattr(response, "parsed", None)
    if parsed is None:
        text = str(getattr(response, "text", None) or "")
        parsed = json.loads(text) if text else {}
    lines = parsed.get("lines") if isinstance(parsed, dict) else None
    if not isinstance(lines, list):
        return []
    return [line for line in lines if isinstance(line, dict) and line.get("text")]


def _font(size: int) -> ImageFont.ImageFont:
    for path in (
        r"C:\Windows\Fonts\malgun.ttf",
        r"C:\Windows\Fonts\malgunbd.ttf",
        r"C:\Windows\Fonts\NanumGothic.ttf",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


def draw_overlay(image_path: Path, lines: list[dict], out_path: Path) -> Path:
    image = Image.open(image_path).convert("RGB")
    # EXIF 회전 반영
    try:
        from PIL import ImageOps

        image = ImageOps.exif_transpose(image)
    except Exception:
        pass
    width, height = image.size
    draw = ImageDraw.Draw(image)
    font = _font(max(14, width // 60))

    for line in lines:
        text = str(line.get("text") or "").strip()
        if not text:
            continue
        try:
            ymin = int(line["ymin"])
            xmin = int(line["xmin"])
            ymax = int(line["ymax"])
            xmax = int(line["xmax"])
        except (KeyError, TypeError, ValueError):
            continue
        left = max(0, int(xmin / 1000 * width))
        top = max(0, int(ymin / 1000 * height))
        right = min(width - 1, int(xmax / 1000 * width))
        bottom = min(height - 1, int(ymax / 1000 * height))
        if right <= left or bottom <= top:
            continue
        draw.rectangle([left, top, right, bottom], outline=(255, 64, 64), width=max(2, width // 400))
        label = text if len(text) <= 40 else text[:39] + "…"
        # 글자 배경
        ty = max(0, top - (font.size + 6))
        bbox = draw.textbbox((left, ty), label, font=font)
        draw.rectangle(bbox, fill=(255, 64, 64))
        draw.text((left, ty), label, fill=(255, 255, 255), font=font)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(out_path, quality=92)
    return out_path


def main() -> int:
    parser = argparse.ArgumentParser(description="OCR 인식 글자 오버레이 이미지 생성")
    parser.add_argument("image", help="원본 이미지 경로")
    parser.add_argument(
        "--out",
        default="",
        help="저장 경로 (기본: <원본이름>_ocr_overlay.jpg)",
    )
    args = parser.parse_args()

    image_path = Path(args.image)
    if not image_path.is_file():
        image_path = ROOT / args.image
    if not image_path.is_file():
        print(f"이미지 없음: {args.image}")
        return 1

    out_path = Path(args.out) if args.out else image_path.with_name(
        f"{image_path.stem}_ocr_overlay.jpg"
    )
    if not out_path.is_absolute():
        out_path = ROOT / out_path

    print("OCR 박스 인식 중…", image_path)
    lines = detect_text_boxes(image_path.read_bytes())
    print(f"인식 줄 수: {len(lines)}")
    saved = draw_overlay(image_path, lines, out_path)
    print("저장:", saved.resolve())
    for line in lines[:20]:
        print("-", line.get("text"))
    if len(lines) > 20:
        print(f"... 외 {len(lines) - 20}줄")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
