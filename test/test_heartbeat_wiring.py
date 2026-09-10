from pathlib import Path
import unittest


class HeartbeatWiringTest(unittest.TestCase):
    def test_operational_and_dataset_flows_remain_separate(self):
        source = Path("lib/features/biosignal/presentation/screens/heartbeat_screen.dart").read_text(encoding="utf-8")
        self.assertIn("_polar.currentBpmStream.listen", source)
        self.assertIn("_datasetCollector.addPolarBpm", source)
        self.assertIn("_polar.averageBpmStream.listen", source)
        self.assertIn("'/api/v1/biosignal/heart-rate'", source)
        self.assertIn("'source': 'POLAR_30S_AVERAGE'", source)
        self.assertIn("if (userId.isEmpty)", source)
        self.assertIn("for (final subscription in _subscriptions)", source)
        self.assertIn("subscription.cancel()", source)

    def test_baseline_and_average_policy_are_wired_to_live_route(self):
        route_source = Path("lib/main.dart").read_text(encoding="utf-8")
        screen_source = Path(
            "lib/features/biosignal/presentation/screens/heartbeat_screen.dart"
        ).read_text(encoding="utf-8")
        polar_source = Path(
            "lib/features/biosignal/data/polar_service.dart"
        ).read_text(encoding="utf-8")

        self.assertIn("builder: (context, state) => const HeartbeatScreen()", route_source)
        self.assertIn("_baselineRemainingSeconds = 15", screen_source)
        self.assertIn("averageValidHeartRates(_baselineSamples)", screen_source)
        self.assertIn("_polar.startAverageMonitoring()", screen_source)
        self.assertIn("currentAverage: _currentAverageBpm", screen_source)
        self.assertIn(
            "if (_baselineBpm == null && !_isBaselineMeasuring)", screen_source
        )
        self.assertNotIn("15초 기준 심박 재기", screen_source)
        self.assertNotIn("기준 심박 다시 재기", screen_source)
        self.assertNotIn("class _HeartRateMetric", screen_source)
        self.assertNotIn("'정상이에요'", screen_source)
        self.assertNotIn("'조금 빨라요'", screen_source)
        self.assertEqual(screen_source.count("_polar.currentBpmStream.listen"), 1)
        self.assertIn("bool _isAverageMonitoring = false", polar_source)
        self.assertIn("if (_isAverageMonitoring)", polar_source)

    def test_permissions_are_checked_before_scan(self):
        source = Path(
            "lib/features/biosignal/presentation/screens/heartbeat_screen.dart"
        ).read_text(encoding="utf-8")
        permission_check = source.index("permissionStatuses.values.any")
        device_scan = source.index("_polar.findDeviceId")
        self.assertLess(permission_check, device_scan)


if __name__ == "__main__":
    unittest.main()
