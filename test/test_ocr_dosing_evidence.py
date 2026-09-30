"""복용 숫자 출처 보존 및 약별 항목 연결 회귀 테스트 (외부 API 호출 없음)."""
import pytest

from app.services.ocr.parser import parse_prescription_text, filter_to_source


def _table(rows, headers=None):
    headers = headers or ["약품명", "1회 투약량", "1일 투여횟수", "투약일수"]
    return {"cells": [
        {"rowIndex": r, "columnIndex": c, "inferText": value}
        for r, values in enumerate([headers, *rows])
        for c, value in enumerate(values)
    ]}


def test_labelled_numbers_are_not_dropped():
    raw = "아디팜정\n1회 투약량 0.5\n1일 투여횟수 3\n투약일수 7"
    item = parse_prescription_text(raw)["items"][0]
    assert item["dosage"] == "0.5"
    assert item["frequency_per_day"] == 3
    assert item["duration_days"] == 7


def test_table_frequency_survives_text_without_numeric_row():
    raw = "아디팜정\n1회 투약량 0.5\n1일 투여횟수 3\n투약일수 7"
    item = parse_prescription_text(raw, tables=[_table([["아디팜정", "0.5", "3", "7"]])])["items"][0]
    assert item["frequency_per_day"] == 3
    assert item["duration_days"] == 7
    assert not any(key.startswith("_") for key in item)


def test_labels_flattened_to_one_line_still_bind_values():
    item = parse_prescription_text("테스트정\n1회 투약량 0.5 1일 투여횟수 3 투약일수 7")["items"][0]
    assert item["dosage"] == "0.5"
    assert item["frequency_per_day"] == 3
    assert item["duration_days"] == 7


def test_value_on_next_line_requires_matching_label():
    item = parse_prescription_text("테스트정\n1회 투약량\n0.5\n1일 투여횟수\n3\n투약일수\n7")["items"][0]
    assert item["dosage"] == "0.5"
    assert item["frequency_per_day"] == 3
    assert item["duration_days"] == 7


def test_table_coordinates_work_even_when_raw_names_are_reversed():
    result = parse_prescription_text(
        "다른캡슐\n테스트정", tables=[_table([
            ["테스트정", "0.5", "3", "7"], ["다른캡슐", "1.0", "2", "4"],
        ])],
    )
    by_name = {item["drug_name"]: item for item in result["items"]}
    assert (by_name["테스트정"]["frequency_per_day"], by_name["테스트정"]["duration_days"]) == (3, 7)
    assert (by_name["다른캡슐"]["frequency_per_day"], by_name["다른캡슐"]["duration_days"]) == (2, 4)


def test_columns_can_be_in_different_order():
    table = _table([["7", "테스트정", "3", "0.5"]], ["투약일수", "약품명", "1일 투여횟수", "1회 투약량"])
    item = parse_prescription_text("테스트정", tables=[table])["items"][0]
    assert item["dosage"] == "0.5"
    assert item["frequency_per_day"] == 3
    assert item["duration_days"] == 7


def test_labelled_values_do_not_move_to_next_drug():
    raw = "테스트정\n1회 투약량 0.5\n1일 투여횟수 3\n투약일수 7\n다른캡슐\n1회 투약량 1\n1일 투여횟수 2\n투약일수 4"
    by_name = {item["drug_name"]: item for item in parse_prescription_text(raw)["items"]}
    assert len(by_name) == 2
    assert by_name["테스트정"]["duration_days"] == 7
    assert by_name["다른캡슐"]["duration_days"] == 4
    assert by_name["테스트정"]["frequency_per_day"] == 3
    assert by_name["다른캡슐"]["frequency_per_day"] == 2


@pytest.mark.parametrize("cell", ["0 . 5", "0. 5", "0 .5"])
def test_decimal_split_only_inside_known_dose_cell(cell):
    item = parse_prescription_text("테스트정", tables=[_table([["테스트정", cell, "3", "7"]])])["items"][0]
    assert item["dosage"] == "0.5"


@pytest.mark.parametrize("key,column,bad_value", [
    ("dosage", 1, "100mg"), ("dosage", 1, "/1정"),
    ("frequency_per_day", 2, "3.5"), ("frequency_per_day", 2, "30"),
    ("duration_days", 3, "100일리그"), ("duration_days", 3, "2026-09-29"),
])
def test_invalid_cell_is_not_accepted_as_dosing(key, column, bad_value):
    row = ["테스트정", "0.5", "3", "7"]
    row[column] = bad_value
    item = parse_prescription_text("테스트정", tables=[_table([row])])["items"][0]
    assert item.get(key) is None


def test_table_frequency_conflicting_with_label_requires_confirmation():
    raw = "테스트정\n1일 투여횟수 2"
    item = parse_prescription_text(raw, tables=[_table([["테스트정", "0.5", "3", "7"]])])["items"][0]
    assert item.get("frequency_per_day") is None
    assert "확인" in item["warning_note"]


def test_table_frequency_conflicting_with_common_instruction_is_not_auto_selected():
    item = parse_prescription_text("1일 2회\n테스트정", tables=[_table([["테스트정", "0.5", "3", "7"]])])["items"][0]
    assert item.get("frequency_per_day") is None
    assert "확인" in item["warning_note"]


def test_conflicting_labels_never_choose_first_number():
    item = parse_prescription_text("테스트정\n투약일수 4\n투약일수 7")["items"][0]
    assert item.get("duration_days") is None
    assert "확인" in item["warning_note"]


def test_bare_table_flag_is_not_enough_evidence():
    result = filter_to_source({"items": [{"drug_name": "테스트정", "duration_days": 100,
                                           "_duration_from_table": True}]}, "테스트정100mg")
    assert result["items"][0].get("duration_days") is None


def test_labels_do_not_use_header_numbers_or_strength_as_values():
    item = parse_prescription_text("테스트정100mg\n1회 투약량\n1일 투여횟수\n투약일수")["items"][0]
    assert item.get("dosage") is None
    assert item.get("frequency_per_day") is None
    assert item.get("duration_days") is None


def test_pipeline_diagnostics_measure_missing_values_without_raw_text(caplog):
    import logging
    from app.services.ocr.pipeline import run_ocr_text_pipeline
    with caplog.at_level(logging.INFO, logger="uvicorn.error"):
        result = run_ocr_text_pipeline("합성시험정\n1회 투약량 0.5\n1일 투여횟수 3\n투약일수 7")
    assert result.ok is True
    assert result.trace["parser_elapsed_ms"] >= 0
    assert result.trace["dosing_diagnostics"]["missing_counts"] == {
        "dosage": 0, "frequency_per_day": 0, "duration_days": 0,
    }
    assert "[OCR_DOSING]" in caplog.text
    assert "합성시험정" not in caplog.text


@pytest.mark.parametrize("dose", ["0.5정", "1/2정", "반 알"])
def test_explicit_half_dose_is_preserved_not_truncated_to_zero(dose):
    item = parse_prescription_text("테스트정\n1회 투약량 " + dose + "\n1일 투여횟수 3\n투약일수 7")["items"][0]
    assert float(item["dosage"]) == 0.5
    assert item.get("times_per_take") != 0
    assert item["frequency_per_day"] == 3
