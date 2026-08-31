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


if __name__ == "__main__":
    unittest.main()
