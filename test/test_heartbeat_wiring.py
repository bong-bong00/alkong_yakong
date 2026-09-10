from pathlib import Path
import unittest


class HeartbeatWiringTest(unittest.TestCase):
    """센서 배선이 살아 있는지 지킨다.

    배선은 heartbeat_screen 에서 heart_sensor 로 옮겨졌다. 화면마다 따로
    구현하면 한쪽만 고쳐지고 다른 쪽이 남기 때문이다. 지키려는 것은
    그대로다 — 운영 기록과 데이터셋 수집이 서로 섞이지 않아야 한다.
    """

    SENSOR = Path("lib/features/biosignal/application/heart_sensor.dart")

    def test_operational_and_dataset_flows_remain_separate(self):
        source = self.SENSOR.read_text(encoding="utf-8")
        self.assertIn("_polar.currentBpmStream.listen", source)
        self.assertIn("_datasetCollector.addPolarBpm", source)
        self.assertIn("_polar.averageBpmStream.listen", source)
        self.assertIn("'/api/v1/biosignal/heart-rate'", source)
        self.assertIn("'source': 'POLAR_30S_AVERAGE'", source)
        self.assertIn("if (userId.isEmpty)", source)
        self.assertIn("for (final subscription in _subscriptions)", source)
        self.assertIn("subscription.cancel()", source)

    def test_screens_share_one_sensor(self):
        """화면들이 배선을 다시 구현하지 않고 이 클래스를 쓴다."""
        for screen in (
            "lib/features/biosignal/presentation/screens/measure_screen.dart",
        ):
            source = Path(screen).read_text(encoding="utf-8")
            self.assertIn("HeartSensor", source, msg=screen)
            self.assertNotIn("_polar.startHrStreaming", source, msg=screen)


if __name__ == "__main__":
    unittest.main()
