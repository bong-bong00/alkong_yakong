"""CLOVA OCR fields -> deterministic prescription structure."""

from __future__ import annotations

from dataclasses import dataclass, field
import logging
from time import perf_counter
from typing import Any

from app.services.ocr.engine import extract_raw_text
from app.services.ocr.parser import parse_prescription_text

logger = logging.getLogger("uvicorn.error")


@dataclass
class OcrPipelineResult:
    ok: bool
    raw_text: str = ""
    structured: dict[str, Any] | None = None
    error: str | None = None
    trace: dict[str, Any] = field(default_factory=dict)


def _parse_result(raw_text: str, engine_name: str | None = None, **extra_trace: Any) -> OcrPipelineResult:
    started = perf_counter()
    parsed = parse_prescription_text(raw_text, tables=extra_trace.get("tables"))
    extra_trace["parser_elapsed_ms"] = round((perf_counter() - started) * 1000)
    if not parsed or not parsed.get("items"):
        trace = {"stage": "parser", **extra_trace}
        if engine_name:
            trace["engine"] = engine_name
        return OcrPipelineResult(False, raw_text, error="parse_failed", trace=trace)
    trace = {
        "stage": "done",
        "parser_engine": parsed.get("parser_engine"),
        **extra_trace,
    }
    if engine_name:
        trace["engine"] = engine_name
    trace["dosing_diagnostics"] = parsed.get("dosing_diagnostics") or {}
    logger.info(
        "[OCR_DOSING] engine_elapsed_ms=%s parser_elapsed_ms=%s table_count=%s diagnostics=%s",
        trace.get("engine_elapsed_ms"), trace["parser_elapsed_ms"],
        len(extra_trace.get("tables") or []), trace["dosing_diagnostics"],
    )
    return OcrPipelineResult(True, raw_text, parsed, trace=trace)


def run_ocr_pipeline(image_bytes: bytes) -> OcrPipelineResult:
    started = perf_counter()
    engine = extract_raw_text(image_bytes)
    extra: dict[str, Any] = {"engine_elapsed_ms": round((perf_counter() - started) * 1000)}
    if not engine.ok:
        return OcrPipelineResult(
            False,
            error=engine.error,
            trace={"engine": engine.engine_name, "stage": "engine", **extra},
        )
    if engine.confidence is not None:
        extra["engine_confidence"] = engine.confidence
    if engine.fields:
        extra["fields"] = [dict(field) for field in engine.fields]
    if engine.tables:
        extra["tables"] = [dict(table) for table in engine.tables]
    return _parse_result(engine.raw_text, engine.engine_name, **extra)


def run_ocr_text_pipeline(raw_text: str) -> OcrPipelineResult:
    text = (raw_text or "").strip()
    if not text:
        return OcrPipelineResult(False, error="empty_raw_text", trace={"stage": "input"})
    return _parse_result(text)
