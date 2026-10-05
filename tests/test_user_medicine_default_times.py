from app.services.user_medicines_service import _default_times


def test_missing_times_fall_back_to_daily_frequency_defaults():
    # 같은 처방전을 다시 등록해 시각이 비어 남은 약도 "언제"를 보여 준다.
    assert _default_times(3) == ["08:00", "13:00", "20:00"]
    assert _default_times("1") == ["08:00"]


def test_unknown_frequency_does_not_invent_times():
    assert _default_times(None) == []
    assert _default_times(7) == []
