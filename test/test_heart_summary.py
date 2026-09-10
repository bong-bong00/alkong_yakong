from datetime import datetime, timedelta
import unittest

from app.services.biosignal_service import (
    _best_streak,
    _pair_for,
    _streak,
)


class HeartPairingTest(unittest.TestCase):
    """복약 시각을 기준으로 전·후를 맞춘다."""

    def setUp(self):
        self.taken_at = datetime(2026, 9, 10, 18, 0, 0)

    def test_picks_closest_reading_on_each_side(self):
        readings = [
            (self.taken_at - timedelta(minutes=60), 90),
            (self.taken_at - timedelta(minutes=10), 78),  # 가장 가까운 이전
            (self.taken_at + timedelta(minutes=12), 72),  # 가장 가까운 이후
            (self.taken_at + timedelta(minutes=70), 68),
        ]
        pair = _pair_for(self.taken_at, readings)
        self.assertEqual(pair["before"], 78)
        self.assertEqual(pair["after"], 72)

    def test_readings_outside_the_window_are_ignored(self):
        readings = [
            (self.taken_at - timedelta(hours=5), 80),
            (self.taken_at + timedelta(hours=5), 70),
        ]
        pair = _pair_for(self.taken_at, readings)
        self.assertIsNone(pair["before"])
        self.assertIsNone(pair["after"])

    def test_missing_side_stays_none(self):
        """없는 값을 지어내지 않는다."""
        readings = [(self.taken_at + timedelta(minutes=5), 74)]
        pair = _pair_for(self.taken_at, readings)
        self.assertIsNone(pair["before"])
        self.assertEqual(pair["after"], 74)


class HeartStreakTest(unittest.TestCase):
    def test_unmeasured_days_do_not_break_the_streak(self):
        """센서를 안 찬 날이 "이상한 날"이 되면 안 된다."""
        month = [
            {"day": 1, "after": 72},
            {"day": 2, "after": None},
            {"day": 3, "after": 70},
        ]
        self.assertEqual(_streak(month), 2)

    def test_a_fast_day_breaks_the_streak(self):
        month = [
            {"day": 1, "after": 70},
            {"day": 2, "after": 96},
            {"day": 3, "after": 72},
        ]
        self.assertEqual(_streak(month), 1)
        self.assertEqual(_best_streak(month), 1)

    def test_best_streak_spans_the_whole_month(self):
        month = [
            {"day": 1, "after": 70},
            {"day": 2, "after": 71},
            {"day": 3, "after": 99},
            {"day": 4, "after": 72},
        ]
        self.assertEqual(_best_streak(month), 2)


if __name__ == "__main__":
    unittest.main()
