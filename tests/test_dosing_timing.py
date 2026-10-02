"""처방전 용법 문구에서 복용 시간대를 읽는 규칙.

처방전에는 "아침 약"이라고 안 적혀 있다. 적혀 있는 용법에서 읽어내되,
못 읽으면 지어내지 않고 비워 두는 것이 이 모듈의 핵심이다.
"""

from app.services.ocr.dosing_timing import (
    default_slots_for_frequency,
    read_timing,
    timing_from_usage,
)


def test_meal_instruction_splits_by_frequency():
    # 가장 흔한 처방. 끼니에 맞춰 세 때로 나뉜다.
    assert read_timing("1일 3회 매 식후 30분", 3)["slots"] == ["아침", "점심", "저녁"]
    assert read_timing("1일 2회 식후 30분", 2)["slots"] == ["아침", "저녁"]
    assert read_timing("1일 1회 식후", 1)["slots"] == ["아침"]


def test_bedtime_is_not_turned_into_morning():
    # 이것이 이 모듈을 만든 이유다. 1일 1회만 보고 아침으로 보내면
    # 자기 전에 드실 약을 아침에 드시게 된다.
    assert read_timing("1일 1회 취침 전", 1)["slots"] == ["취침전"]
    assert read_timing("1일 1회 자기 전 복용", 1)["slots"] == ["취침전"]


def test_explicit_slot_words_win():
    assert read_timing("1일 2회 아침 저녁 식후 30분", 2)["slots"] == ["아침", "저녁"]
    assert read_timing("1일 1회 아침 식후", 1)["slots"] == ["아침"]


def test_unknown_timing_stays_empty():
    # 때를 알 수 없으면 비워 둔다. 확인 화면이 사람에게 묻는다.
    assert read_timing("용법: 1일 1회", 1)["slots"] == []
    assert read_timing("", 3)["slots"] == []


def test_slot_count_mismatch_is_not_half_guessed():
    # "아침"만 적혔는데 1일 2회면 나머지 한 번이 언제인지 알 수 없다.
    # 끼니 약이면 아침·저녁으로 메우고, 아니면 모른다고 둔다.
    assert read_timing("1일 2회 아침 식후", 2)["slots"] == ["아침", "저녁"]
    assert read_timing("1일 2회 아침", 2)["slots"] == []


def test_instruction_line_is_kept_for_the_screen():
    timing = read_timing("아디팜정\n1일 3회 매 식후 30분\n7일분", 3)
    assert timing["instruction"] == "1일 3회 매 식후 30분"


def test_official_usage_only_helps_when_timing_is_clear():
    assert timing_from_usage("성인 1일 1회 1정을 취침 전에 경구투여한다.", 1) == ["취침전"]
    # 때를 말하지 않는 허가 용법에서는 아무것도 가져오지 않는다.
    assert timing_from_usage("의사의 처방에 따라 복용한다.", 1) == []
    assert timing_from_usage(None, 1) == []


def test_frequency_default_is_last_resort():
    assert default_slots_for_frequency(3) == ["아침", "점심", "저녁"]
    assert default_slots_for_frequency(2) == ["아침", "저녁"]
    # 하루 네 번 이상은 끼니로 나눌 수 없다. 지어내지 않는다.
    assert default_slots_for_frequency(4) == []
    assert default_slots_for_frequency(None) == []
