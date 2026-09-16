import os
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

import init_db
from app.models.schemas import HeartRateCreate
from app.models.response_schemas import HeartRateResponse
from app.services import biosignal_service


class BiosignalPolicyTest(unittest.TestCase):
    def test_heart_rate_post_only_records_operational_average(self):
        handle, path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        try:
            with patch.object(init_db, "DB_PATH", path):
                init_db.initialize_database()
            conn = sqlite3.connect(path)
            conn.execute(
                "INSERT INTO users (id, name, role) VALUES ('U1', '테스트', 'PATIENT')"
            )
            conn.execute(
                """
                INSERT INTO guardians (
                    id, user_id, guardian_name, relationship,
                    phone, notification_enabled
                ) VALUES ('G1', 'U1', '보호자', '가족', '01000000000', 1)
                """
            )
            conn.commit()
            conn.close()

            def connection():
                candidate = sqlite3.connect(path)
                candidate.row_factory = sqlite3.Row
                candidate.execute("PRAGMA foreign_keys = ON")
                return candidate

            with patch.object(biosignal_service, "get_connection", connection):
                result = biosignal_service.save_heart_rate(
                    HeartRateCreate(
                        user_id="U1",
                        bpm=160,
                        source="POLAR_30S_AVERAGE",
                    )
                )

            conn = sqlite3.connect(path)
            counts = {
                table: conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                for table in (
                    "heart_rate_logs",
                    "baseline_heart_rate",
                    "abnormal_events",
                    "notifications",
                )
            }
            source = conn.execute(
                "SELECT source FROM heart_rate_logs"
            ).fetchone()[0]
            conn.close()

            self.assertEqual(counts["heart_rate_logs"], 1)
            self.assertEqual(counts["baseline_heart_rate"], 0)
            self.assertEqual(counts["abnormal_events"], 0)
            self.assertEqual(counts["notifications"], 0)
            self.assertEqual(source, "POLAR_30S_AVERAGE")
            self.assertIsNone(result["baseline"])
            self.assertIsNone(result["abnormal_event"])
            response = HeartRateResponse.model_validate(result)
            self.assertIsNone(response.baseline)
        finally:
            try:
                conn.close()
            except Exception:
                pass
            os.remove(path)


if __name__ == "__main__":
    unittest.main()
