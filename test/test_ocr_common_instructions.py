"""사진 양식을 옮긴 합성 OCR 원문 회귀 테스트. 실제 CLOVA 응답은 아님."""

from app.services.ocr.parser import (
    _dosing_from_window,
    _normalize_table_dosing,
    parse_prescription_text,
)


def test_common_header_fills_five_medicines_without_inventing_take_amount():
    raw = """1일 3회 4일분
약품명 효능안내 주의사항 약품사진
옴니세프캡슐100밀리그램(100.1g/1캡슐)
약효 세균감염증 치료제
헤라신정250밀리그램(0.25g/1정)
약효 세균감염증 치료제
비포린비정10mg/1정
약효 알레르기질환약
엑스노펜세미정[1정]
약효 진통제
펠루비에스정[36.73mg/1정]
약효 해열진통소염제
"""
    result = parse_prescription_text(raw)
    assert result is not None
    assert len(result["items"]) == 5
    for item in result["items"]:
        assert item.get("frequency_per_day") == 3
        assert item.get("duration_days") == 4
        assert not item.get("dosage")
        assert not item.get("times_per_take")


def test_strength_after_dose_pair_is_not_duration():
    result = _dosing_from_window("테스트정 0.50 3 함량 100밀리그램")
    assert result.get("frequency_per_day") == 3
    assert "duration_days" not in result
    assert "duration_days" not in _dosing_from_window("테스트정 0.50 3 설명 100")


def test_strength_triple_and_product_decimal_are_not_dosing():
    assert _dosing_from_window("테스트정 0.50 3 100밀리그램") == {
        "dosage": "0.50", "frequency_per_day": 3,
    }
    assert _dosing_from_window("테스트정36.73mg/1정") == {}
    assert _dosing_from_window("테스트정 36.73 mg / 1정") == {}


def test_large_frequency_is_not_reinterpreted_as_days_or_one_daily():
    item = _normalize_table_dosing([
        {"drug_name": "테스트정", "frequency_per_day": 100},
    ])[0]
    assert "frequency_per_day" not in item
    assert "duration_days" not in item


def test_individual_directions_override_common_header():
    result = parse_prescription_text(
        "1일 3회 4일분\n테스트정 1일 2회 7일분\n다른캡슐100mg\n"
    )
    assert result is not None
    by_name = {item["drug_name"]: item for item in result["items"]}
    assert by_name["테스트정"]["frequency_per_day"] == 2
    assert by_name["테스트정"]["duration_days"] == 7
    assert by_name["다른캡슐"]["frequency_per_day"] == 3
    assert by_name["다른캡슐"]["duration_days"] == 4


def test_unread_or_conflicting_common_numbers_are_not_guessed():
    result = parse_prescription_text("1일 ?회 ?일분\n테스트정100mg\n")
    assert result is not None
    item = result["items"][0]
    assert "frequency_per_day" not in item
    assert "duration_days" not in item
    result = parse_prescription_text("1일 2회 1일 3회 4일분 7일분\n테스트정\n")
    assert result is not None
    assert "frequency_per_day" not in result["items"][0]
    assert "duration_days" not in result["items"][0]


def test_split_common_header_and_glued_instruction_keep_candidate():
    result = parse_prescription_text("1일\n3\n회\n4\n일분헤라신정250밀리그램\n")
    assert result is not None
    assert any(item["drug_name"] == "헤라신정" for item in result["items"])
    assert result["items"][0].get("frequency_per_day") == 3
    assert result["items"][0].get("duration_days") == 4


def test_name_only_clova_table_keeps_names_without_dosing_columns():
    table = {"cells": [
        {"rowIndex": 0, "columnIndex": 0, "inferText": "약품명"},
        {"rowIndex": 0, "columnIndex": 1, "inferText": "효능안내"},
        {"rowIndex": 1, "columnIndex": 0, "inferText": "테스트정100밀리그램"},
        {"rowIndex": 1, "columnIndex": 1, "inferText": "세균감염증 치료제"},
        {"rowIndex": 2, "columnIndex": 0, "inferText": "다른캡슐250mg"},
    ]}
    result = parse_prescription_text(
        "1일 3회 4일분\n세균감염증치료제테스트정100밀리그램\n다른캡슐250mg",
        tables=[table],
    )
    assert result is not None
    assert {item["drug_name"] for item in result["items"]} == {"테스트정", "다른캡슐"}
    assert all(item.get("duration_days") == 4 for item in result["items"])
