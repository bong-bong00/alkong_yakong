"""OCR pipeline: image/text input -> raw text -> structured prescription."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from app.services.ocr.engine import extract_raw_text
from app.services.ocr.parser import parse_prescription_text


@dataclass
class OcrPipelineResult:
    ok: bool
    raw_text: str = ""
    structured: dict[str, Any] | None = None
    error: str | None = None
    trace: dict[str, Any] = field(default_factory=dict)


def _parse_result(raw_text: str, engine_name: str | None = None) -> OcrPipelineResult:
    parsed = parse_prescription_text(raw_text)
    if not parsed or not parsed.get("items"):
        trace = {"stage": "parser"}
        if engine_name:
            trace["engine"] = engine_name
        return OcrPipelineResult(False, raw_text, error="parse_failed", trace=trace)
    trace = {"stage": "done"}
    if engine_name:
        trace["engine"] = engine_name
    return OcrPipelineResult(True, raw_text, parsed, trace=trace)


def run_ocr_pipeline(image_bytes: bytes) -> OcrPipelineResult:
    engine = extract_raw_text(image_bytes)
    if not engine.ok:
        return OcrPipelineResult(
            False,
            error=engine.error,
            trace={"engine": engine.engine_name, "stage": "engine"},
        )
    return _parse_result(engine.raw_text, engine.engine_name)


def run_ocr_text_pipeline(raw_text: str) -> OcrPipelineResult:
    text = (raw_text or "").strip()
    if not text:
        return OcrPipelineResult(False, error="empty_raw_text", trace={"stage": "input"})
    return _parse_result(text)
