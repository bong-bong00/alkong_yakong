import unittest
from unittest.mock import Mock, patch

import requests

from app.services import medication_feature_dur_client as remote_dur


class MedicationFeatureDurClientTest(unittest.TestCase):
    selected = {"medicine_code": "100", "product_name": "등록약정"}

    @staticmethod
    def response(payload, *, status_code=200):
        response = Mock()
        response.json.return_value = payload
        response.raise_for_status.return_value = None
        response.status_code = status_code
        return response

    def medicines(self):
        return {
            "medicines": [
                {
                    "medicine_code": "100",
                    "product_name": "등록약정",
                    "status": "active",
                }
            ]
        }

    def call(self):
        return remote_dur.load_remote_combination_context(
            user_id="user-1",
            selected_medicine=self.selected,
        )

    def test_risk_result_uses_medication_service_only(self):
        match = {
            "type": "병용금기",
            "medicine_codes_a": ["100"],
            "medicine_codes_b": ["200"],
            "reason": "1~2 mg 조건에서 주의",
        }
        with (
            patch.object(remote_dur, "MEDICATION_FEATURE_BASE_URL", "https://med.example"),
            patch.object(remote_dur.requests, "get", return_value=self.response(self.medicines())) as get,
            patch.object(
                remote_dur.requests,
                "post",
                return_value=self.response(
                    {
                        "assessment_status": "RISK_FOUND",
                        "analysis_complete": True,
                        "incomplete": False,
                        "has_risk": True,
                        "matches": [match],
                    }
                ),
            ) as post,
        ):
            result = self.call()
        self.assertEqual(result["status"], "current")
        self.assertEqual(result["items"], [match])
        self.assertIn("/api/v1/users/user-1/medicines", get.call_args.args[0])
        self.assertEqual(post.call_args.kwargs["json"], {"user_id": "user-1", "medicine_codes": []})

    def test_completed_zero_result_is_current_not_incomplete(self):
        with (
            patch.object(remote_dur, "MEDICATION_FEATURE_BASE_URL", "https://med.example"),
            patch.object(remote_dur.requests, "get", return_value=self.response(self.medicines())),
            patch.object(
                remote_dur.requests,
                "post",
                return_value=self.response(
                    {
                        "assessment_status": "SAFE",
                        "analysis_complete": True,
                        "incomplete": False,
                        "has_risk": False,
                        "matches": [],
                    }
                ),
            ),
        ):
            result = self.call()
        self.assertEqual(result, {"status": "current", "items": [], "has_risk": False, "reason": None})

    def test_incomplete_is_never_safe(self):
        with (
            patch.object(remote_dur, "MEDICATION_FEATURE_BASE_URL", "https://med.example"),
            patch.object(remote_dur.requests, "get", return_value=self.response(self.medicines())),
            patch.object(
                remote_dur.requests,
                "post",
                return_value=self.response(
                    {
                        "assessment_status": "INCOMPLETE",
                        "analysis_complete": False,
                        "incomplete": True,
                        "has_risk": False,
                        "matches": [],
                    }
                ),
            ),
        ):
            result = self.call()
        self.assertEqual(result["status"], "incomplete")
        self.assertIsNone(result["has_risk"])

    def test_incomplete_flag_is_never_safe_even_if_other_fields_say_complete(self):
        with (
            patch.object(remote_dur, "MEDICATION_FEATURE_BASE_URL", "https://med.example"),
            patch.object(remote_dur.requests, "get", return_value=self.response(self.medicines())),
            patch.object(
                remote_dur.requests,
                "post",
                return_value=self.response(
                    {
                        "assessment_status": "SAFE",
                        "analysis_complete": True,
                        "incomplete": True,
                        "has_risk": False,
                        "matches": [],
                    }
                ),
            ),
        ):
            result = self.call()
        self.assertEqual(result["status"], "incomplete")
        self.assertIsNone(result["has_risk"])

    def test_timeout_http_and_malformed_are_not_safe(self):
        failures = [
            requests.Timeout("timeout"),
            requests.HTTPError("503"),
        ]
        for failure in failures:
            with (
                self.subTest(failure=type(failure).__name__),
                patch.object(remote_dur, "MEDICATION_FEATURE_BASE_URL", "https://med.example"),
                patch.object(remote_dur.requests, "get", side_effect=failure),
            ):
                result = self.call()
                self.assertNotEqual(result["status"], "current")
                self.assertIsNone(result["has_risk"])

        with (
            patch.object(remote_dur, "MEDICATION_FEATURE_BASE_URL", "https://med.example"),
            patch.object(remote_dur.requests, "get", return_value=self.response(self.medicines())),
            patch.object(remote_dur.requests, "post", return_value=self.response({"assessment_status": "SAFE"})),
        ):
            result = self.call()
        self.assertEqual(result["status"], "malformed")
        self.assertIsNone(result["has_risk"])

    def test_missing_or_mismatched_selected_identity_stops_before_analysis(self):
        for selected in (
            {"medicine_code": "", "product_name": "등록약정"},
            {"medicine_code": "999", "product_name": "등록약정"},
            {"medicine_code": "100", "product_name": "다른약정"},
        ):
            with (
                self.subTest(selected=selected),
                patch.object(remote_dur, "MEDICATION_FEATURE_BASE_URL", "https://med.example"),
                patch.object(remote_dur.requests, "get", return_value=self.response(self.medicines())),
                patch.object(remote_dur.requests, "post") as post,
            ):
                result = remote_dur.load_remote_combination_context(
                    user_id="user-1",
                    selected_medicine=selected,
                )
                self.assertEqual(result["status"], "missing")
                post.assert_not_called()

    def test_all_medicines_uses_active_ocr_and_manual_rows_for_one_dur_analysis(self):
        medicines = {
            "medicines": [
                {"medicine_code": "100", "official_product_name": "OCR등록약정", "status": "active"},
                {"medicine_code": "200", "product_name": "손입력약정", "status": "active"},
                {"medicine_code": "300", "product_name": "지난약정", "status": "inactive"},
            ]
        }
        with (
            patch.object(remote_dur, "MEDICATION_FEATURE_BASE_URL", "https://med.example"),
            patch.object(remote_dur.requests, "get", return_value=self.response(medicines)),
            patch.object(
                remote_dur.requests,
                "post",
                return_value=self.response(
                    {
                        "assessment_status": "SAFE",
                        "analysis_complete": True,
                        "incomplete": False,
                        "has_risk": False,
                        "matches": [],
                    }
                ),
            ) as post,
        ):
            result = remote_dur.load_remote_combination_context(
                user_id="user-1",
                selected_medicine=None,
            )
        self.assertEqual(result["status"], "current")
        self.assertFalse(result["has_risk"])
        post.assert_called_once()
        self.assertEqual(post.call_args.kwargs["json"], {"user_id": "user-1", "medicine_codes": []})

    def test_all_medicines_distinguishes_empty_failure_and_incomplete_identity(self):
        cases = (
            ({"medicines": []}, "empty"),
            ({"medicines": [{"medicine_code": "100", "status": "active"}]}, "incomplete"),
            (
                {
                    "medicines": [
                        {"medicine_code": "100", "product_name": "첫이름", "status": "active"},
                        {"medicine_code": "100", "product_name": "다른이름", "status": "active"},
                    ]
                },
                "incomplete",
            ),
        )
        for payload, expected_status in cases:
            with (
                self.subTest(expected_status=expected_status),
                patch.object(remote_dur, "MEDICATION_FEATURE_BASE_URL", "https://med.example"),
                patch.object(remote_dur.requests, "get", return_value=self.response(payload)),
                patch.object(remote_dur.requests, "post") as post,
            ):
                result = remote_dur.load_remote_combination_context(
                    user_id="user-1",
                    selected_medicine=None,
                )
                self.assertEqual(result["status"], expected_status)
                self.assertIsNone(result["has_risk"])
                post.assert_not_called()

        with (
            patch.object(remote_dur, "MEDICATION_FEATURE_BASE_URL", "https://med.example"),
            patch.object(remote_dur.requests, "get", side_effect=requests.Timeout("timeout")),
        ):
            result = remote_dur.load_remote_combination_context(
                user_id="user-1",
                selected_medicine=None,
            )
        self.assertEqual(result["status"], "missing")
        self.assertEqual(result["reason"], "medication_service_unavailable")


if __name__ == "__main__":
    unittest.main()
