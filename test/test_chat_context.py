import json
import os
import sqlite3
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from fastapi import HTTPException

from app.services import chat_context_service, gemini_service
from app.services.mfds_drug_permission import client as permission_client
from app.services.mfds_drug_permission import db as permission_db
from app.services.chat_context_service import (
    build_grounded_chat_prompt,
    classify_question,
    general_conversation_reply,
    is_safety_question,
    load_latest_dur_context,
    resolve_question_intents,
    select_official_context,
)


def _database(*, current, analyzed=None, matches=None, include_result=True):
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        CREATE TABLE medicines (medicine_code TEXT PRIMARY KEY, ingredient TEXT);
        CREATE TABLE user_medicines (id INTEGER PRIMARY KEY, user_id TEXT, medicine_code TEXT, is_active INTEGER);
        CREATE TABLE risk_results (id INTEGER PRIMARY KEY, user_id TEXT, analyzed_ingredients TEXT, matches_json TEXT, created_at TEXT);
        CREATE TABLE dur_taboo (id INTEGER PRIMARY KEY, external_id TEXT, min_age INTEGER, max_age INTEGER, pregnancy_grade TEXT, notification_date TEXT, raw_json TEXT, updated_at TEXT);
        """
    )
    for index, ingredient in enumerate(current, 1):
        code = f"M{index}"
        conn.execute("INSERT INTO medicines VALUES (?, ?)", (code, ingredient))
        conn.execute("INSERT INTO user_medicines VALUES (?, 'U1', ?, 1)", (index, code))
    if include_result:
        conn.execute(
            "INSERT INTO risk_results VALUES (1, 'U1', ?, ?, '2026-01-01')",
            (
                json.dumps(analyzed if analyzed is not None else current, ensure_ascii=False),
                json.dumps(matches or [], ensure_ascii=False),
            ),
        )
    conn.commit()
    return conn


class ChatContextTest(unittest.TestCase):
    def _run_permission_general(
        self,
        *,
        intent,
        permission_fields,
        e_drug_result=None,
        e_drug_error=None,
        permission_verified=True,
    ):
        selected = {"medicine_code": "202400001", "product_name": "공식허가약정"}
        permission = {
            **selected,
            "source": "식약처 의약품 제품 허가정보",
            "_permission_identity_verified": permission_verified,
            **permission_fields,
        }
        fake_client = MagicMock()
        fake_client.__enter__.return_value = fake_client
        fake_client.__exit__.return_value = False
        fetch_effect = e_drug_error if e_drug_error is not None else None
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch("google.genai.Client", return_value=fake_client),
            patch(
                "app.services.external_api_service.fetch_e_drug_info",
                return_value=e_drug_result,
                side_effect=fetch_effect,
            ),
            patch.object(
                gemini_service,
                "_with_official_permission_ingredient",
                return_value=permission,
            ) as enrich,
            patch.object(
                gemini_service,
                "_generate_content_with_retry",
                side_effect=[
                    SimpleNamespace(parsed={"drug_names": []}),
                    SimpleNamespace(text="공식 허가정보만 근거로 작성한 충분한 설명입니다."),
                ],
            ) as generate,
        ):
            reply = gemini_service.generate_chat_response(
                "빠른 질문", user_id="U1", selected_medicine=selected, intent=intent
            )
        return reply, enrich, generate

    def _run_permission_only_safety(self, *, intent, e_drug_result=None, e_drug_error=None):
        selected = {
            "medicine_code": "202400001",
            "product_name": "공식허가약정",
        }
        permission_detail = {
            "ITEM_SEQ": "202400001",
            "ITEM_NAME": "공식허가약정",
            "MAIN_ITEM_INGR": "공식성분 100mg",
        }
        fake_client = MagicMock()
        fake_client.__enter__.return_value = fake_client
        fake_client.__exit__.return_value = False
        fetch_effect = e_drug_error if e_drug_error is not None else None
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch("google.genai.Client", return_value=fake_client),
            patch.object(
                gemini_service,
                "_generate_content_with_retry",
                return_value=SimpleNamespace(parsed={"drug_names": []}),
            ),
            patch(
                "app.services.external_api_service.fetch_e_drug_info",
                return_value=e_drug_result,
                side_effect=fetch_effect,
            ),
            patch(
                "app.services.mfds_drug_permission.db.find_permission_product_by_item_seq",
                return_value=None,
            ),
            patch(
                "app.services.mfds_drug_permission.client.fetch_permission_detail",
                return_value=permission_detail,
            ),
            patch(
                "app.services.dur_service.analyze_dur_consultation",
                return_value={"status": "current", "items": []},
            ) as analyze,
        ):
            reply = gemini_service.generate_chat_response(
                "빠른 질문",
                user_id="U1",
                selected_medicine=selected,
                intent=intent,
            )
        return reply, analyze

    def test_permission_db_item_seq_lookup_is_exact(self):
        handle = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        db_path = handle.name
        handle.close()
        try:
            with patch.object(permission_db, "DB_PATH", db_path):
                permission_db.initialize_permission_db()
                conn = permission_db.get_permission_connection()
                try:
                    conn.execute(
                        """
                        INSERT INTO products (
                            item_seq, item_name, name_compact,
                            main_item_ingr, item_ingr_name
                        ) VALUES (?, ?, ?, ?, ?)
                        """,
                        (
                            "198700430",
                            "알마겔정(알마게이트)(수출명:유한가스트라겔정)",
                            "알마겔정(알마게이트)(수출명:유한가스트라겔정)",
                            "알마게이트 500mg",
                            "알마게이트",
                        ),
                    )
                    conn.commit()
                finally:
                    conn.close()

                row = permission_db.find_permission_product_by_item_seq(
                    "198700430"
                )
                missing = permission_db.find_permission_product_by_item_seq(
                    "198700431"
                )

            self.assertEqual(row["main_item_ingr"], "알마게이트 500mg")
            self.assertIsNone(missing)
        finally:
            os.unlink(db_path)

    def test_permission_detail_filters_name_results_by_exact_item_seq(self):
        response = MagicMock()
        response.json.return_value = {
            "body": {
                "items": [
                    {"ITEM_SEQ": "OTHER", "ITEM_NAME": "동명이품목"},
                    {"ITEM_SEQ": "198700430", "ITEM_NAME": "알마겔정"},
                ]
            }
        }
        with (
            patch.object(permission_client, "MFDS_DRUG_PERMISSION_API_KEY", "key"),
            patch.object(permission_client.requests, "get", return_value=response) as get,
        ):
            item = permission_client.fetch_permission_detail(
                "알마겔정",
                item_seq="198700430",
            )

        response.raise_for_status.assert_called_once_with()
        self.assertEqual(item["ITEM_SEQ"], "198700430")
        params = get.call_args.kwargs["params"]
        self.assertEqual(params["item_name"], "알마겔정")
        self.assertNotIn("item_seq", params)
        self.assertEqual(params["numOfRows"], 100)

    def test_selected_medicine_ingredient_uses_exact_permission_item_seq(self):
        official = {
            "medicine_code": "198700430",
            "product_name": "알마겔정(알마게이트)(수출명:유한가스트라겔정)",
            "ingredient": None,
            "efficacy": "공식 효능",
            "source": "e약은요",
        }
        permission_row = {
            "item_seq": "198700430",
            "item_name": "알마겔정(알마게이트)(수출명:유한가스트라겔정)",
            "main_item_ingr": "알마게이트 500mg",
            "item_ingr_name": "알마게이트",
        }
        with (
            patch(
                "app.services.mfds_drug_permission.db.find_permission_product_by_item_seq",
                return_value=permission_row,
            ) as find_by_seq,
            patch(
                "app.services.mfds_drug_permission.client.fetch_permission_detail"
            ) as fetch_detail,
        ):
            enriched = gemini_service._with_official_permission_ingredient(official)

        find_by_seq.assert_called_once_with("198700430")
        fetch_detail.assert_not_called()
        self.assertEqual(enriched["ingredient"], "알마게이트 500mg")
        self.assertEqual(enriched["efficacy"], "공식 효능")
        self.assertEqual(enriched["source"], "e약은요")

    def test_permission_api_fallback_requires_exact_code_and_name(self):
        official = {
            "medicine_code": "198700430",
            "product_name": "알마겔정(알마게이트)(수출명:유한가스트라겔정)",
            "ingredient": None,
        }
        api_detail = {
            "ITEM_SEQ": "198700430",
            "ITEM_NAME": "알마겔정(알마게이트)(수출명:유한가스트라겔정)",
            "MAIN_ITEM_INGR": "알마게이트 500mg",
            "ITEM_INGR_NAME": "알마게이트",
        }
        with (
            patch(
                "app.services.mfds_drug_permission.db.find_permission_product_by_item_seq",
                return_value=None,
            ),
            patch(
                "app.services.mfds_drug_permission.client.fetch_permission_detail",
                return_value=api_detail,
            ) as fetch_detail,
        ):
            enriched = gemini_service._with_official_permission_ingredient(official)

        fetch_detail.assert_called_once_with(
            "알마겔정(알마게이트)(수출명:유한가스트라겔정)",
            item_seq="198700430",
        )
        self.assertEqual(enriched["ingredient"], "알마게이트 500mg")

    def test_permission_api_fallback_rejects_item_seq_mismatch(self):
        selected = {
            "medicine_code": "202400001",
            "product_name": "공식허가약정",
            "ingredient": None,
        }
        detail = {
            "ITEM_SEQ": "DIFFERENT",
            "ITEM_NAME": "공식허가약정",
            "MAIN_ITEM_INGR": "공식성분 100mg",
        }
        with (
            patch(
                "app.services.mfds_drug_permission.db.find_permission_product_by_item_seq",
                return_value=None,
            ),
            patch(
                "app.services.mfds_drug_permission.client.fetch_permission_detail",
                return_value=detail,
            ),
        ):
            result = gemini_service._with_official_permission_ingredient(selected)
        self.assertIsNone(result["ingredient"])

    def test_permission_api_fallback_rejects_product_name_mismatch(self):
        selected = {
            "medicine_code": "202400001",
            "product_name": "공식허가약정",
            "ingredient": None,
        }
        detail = {
            "ITEM_SEQ": "202400001",
            "ITEM_NAME": "다른공식제품정",
            "MAIN_ITEM_INGR": "공식성분 100mg",
        }
        with (
            patch(
                "app.services.mfds_drug_permission.db.find_permission_product_by_item_seq",
                return_value=None,
            ),
            patch(
                "app.services.mfds_drug_permission.client.fetch_permission_detail",
                return_value=detail,
            ),
        ):
            result = gemini_service._with_official_permission_ingredient(selected)
        self.assertIsNone(result["ingredient"])

    def test_permission_only_selected_medicine_reaches_combination_consultation(self):
        reply, analyze = self._run_permission_only_safety(
            intent="combination",
            e_drug_result=None,
        )
        self.assertIn("해당하는 정보를 찾지 못했어요", reply)
        self.assertEqual(
            analyze.call_args.kwargs["selected_medicine"]["ingredient"],
            "공식성분 100mg",
        )
        self.assertEqual(analyze.call_args.kwargs["risk_types"], {"병용금기"})

    def test_e_drug_error_uses_exact_permission_fallback(self):
        reply, analyze = self._run_permission_only_safety(
            intent="combination",
            e_drug_error=RuntimeError("upstream unavailable"),
        )
        self.assertIn("해당하는 정보를 찾지 못했어요", reply)
        analyze.assert_called_once()

    def test_permission_only_selected_medicine_reaches_duplicate_consultation(self):
        reply, analyze = self._run_permission_only_safety(
            intent="duplicate",
            e_drug_result=None,
        )
        self.assertIn("성분이나 비슷한 효과가 겹친다는 정보를 확인한 공식 자료에서는 찾지 못했어요", reply)
        self.assertIn("모든 위험이 없다는 뜻은 아니에요", reply)
        self.assertEqual(
            analyze.call_args.kwargs["risk_types"],
            {"중복성분", "효능군중복"},
        )

    def test_duplicate_positive_match_keeps_gemini_explanation_flow(self):
        selected = {"medicine_code": "202400001", "product_name": "공식허가약정"}
        verified = {
            **selected,
            "ingredient": "공식성분 100mg",
            "_permission_identity_verified": True,
        }
        fake_client = MagicMock()
        fake_client.__enter__.return_value = fake_client
        fake_client.__exit__.return_value = False
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch("google.genai.Client", return_value=fake_client),
            patch("app.services.external_api_service.fetch_e_drug_info", return_value=None),
            patch.object(gemini_service, "_with_official_permission_ingredient", return_value=verified),
            patch(
                "app.services.dur_service.analyze_dur_consultation",
                return_value={
                    "status": "current",
                    "items": [{"type": "중복성분", "reason": "공식 중복 근거"}],
                    "reason": None,
                },
            ),
            patch("app.services.chat_context_service.enrich_dur_matches", side_effect=lambda items: items),
            patch.object(
                gemini_service,
                "_generate_content_with_retry",
                side_effect=[
                    SimpleNamespace(parsed={"drug_names": []}),
                    SimpleNamespace(text="공식 중복 결과를 이해하기 쉽게 설명한 답변입니다."),
                ],
            ) as generate,
        ):
            reply = gemini_service.generate_chat_response(
                "빠른 질문", user_id="U1", selected_medicine=selected, intent="duplicate"
            )
        self.assertIn("공식 중복 결과", reply)
        self.assertNotIn("확인한 공식 자료에서는 찾지 못했어요", reply)
        self.assertEqual(generate.call_count, 2)

    def test_duplicate_dur_failure_is_not_reported_as_zero_match(self):
        selected = {"medicine_code": "202400001", "product_name": "공식허가약정"}
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch("google.genai.Client"),
            patch("app.services.external_api_service.fetch_e_drug_info", return_value=None),
            patch.object(
                gemini_service,
                "_with_official_permission_ingredient",
                return_value={**selected, "ingredient": "공식성분 100mg"},
            ),
            patch.object(
                gemini_service,
                "_generate_content_with_retry",
                return_value=SimpleNamespace(parsed={"drug_names": []}),
            ),
            patch(
                "app.services.dur_service.analyze_dur_consultation",
                return_value={
                    "status": "missing",
                    "items": [],
                    "reason": "dur_data_unavailable",
                },
            ),
        ):
            reply = gemini_service.generate_chat_response(
                "빠른 질문", user_id="U1", selected_medicine=selected, intent="duplicate"
            )
        self.assertIn("지금은 약을 함께 사용할 때 주의할 공식 정보를 확인하지 못했어요", reply)
        self.assertNotIn("확인한 공식 자료에서는 찾지 못했어요", reply)

    def test_duplicate_missing_ingredient_is_not_reported_as_zero_match(self):
        selected = {"medicine_code": "202400001", "product_name": "공식허가약정"}
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch("app.services.external_api_service.fetch_e_drug_info", return_value=None),
            patch.object(
                gemini_service,
                "_with_official_permission_ingredient",
                return_value={**selected, "ingredient": None},
            ),
        ):
            reply = gemini_service.generate_chat_response(
                "빠른 질문", user_id="U1", selected_medicine=selected, intent="duplicate"
            )
        self.assertIn("선택한 약의 성분을 공식 자료에서 확인하지 못했어요", reply)
        self.assertNotIn("확인한 공식 자료에서는 찾지 못했어요", reply)

    def test_duplicate_zero_match_message_does_not_apply_to_other_safety_intents(self):
        for intent in ("combination", "age", "pregnancy"):
            with self.subTest(intent=intent):
                reply, _ = self._run_permission_only_safety(intent=intent)
                self.assertNotIn("성분이나 비슷한 효과가 겹친다는 정보", reply)

    def test_unverified_selected_medicine_keeps_missing_fallback(self):
        selected = {
            "medicine_code": "202400001",
            "product_name": "검증실패약정",
        }
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch(
                "app.services.external_api_service.fetch_e_drug_info",
                return_value=None,
            ),
            patch.object(
                gemini_service,
                "_with_official_permission_ingredient",
                return_value={**selected, "ingredient": None},
            ),
            patch("app.services.dur_service.analyze_dur_consultation") as analyze,
        ):
            reply = gemini_service.generate_chat_response(
                "빠른 질문",
                user_id="U1",
                selected_medicine=selected,
                intent="combination",
            )
        self.assertIn("함께 사용하면 안 되는 조합이 있는지 확인한 결과를 찾지 못했어요", reply)
        analyze.assert_not_called()

    def test_permission_only_efficacy_uses_exact_official_document(self):
        selected = {
            "medicine_code": "202400001",
            "product_name": "공식허가약정",
        }
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch(
                "app.services.external_api_service.fetch_e_drug_info",
                return_value=None,
            ),
            patch.object(
                gemini_service,
                "_with_official_permission_ingredient",
                return_value={
                    **selected,
                    "ingredient": "공식성분 100mg",
                    "efficacy": "공식 허가 효능",
                    "source": "식약처 의약품 제품 허가정보",
                    "_permission_identity_verified": True,
                },
            ),
            patch("google.genai.Client") as client,
            patch.object(
                gemini_service,
                "_generate_content_with_retry",
                side_effect=[
                    SimpleNamespace(parsed={"drug_names": []}),
                    SimpleNamespace(text="공식 허가정보만 근거로 작성한 충분한 설명입니다."),
                ],
            ) as generate,
        ):
            reply = gemini_service.generate_chat_response(
                "효능을 알려줘",
                user_id="U1",
                selected_medicine=selected,
                intent="efficacy",
            )
        self.assertEqual(reply, "공식 허가정보만 근거로 작성한 충분한 설명입니다.")
        self.assertEqual(generate.call_count, 2)
        self.assertIn("공식 허가 효능", generate.call_args.kwargs["contents"])

    def test_e_drug_efficacy_has_priority_without_permission_fallback(self):
        e_drug = {
            "medicine_code": "202400001",
            "product_name": "공식허가약정",
            "efficacy": "e약은요 공식 효능",
            "source": "e약은요",
        }
        reply, enrich, generate = self._run_permission_general(
            intent="efficacy",
            permission_fields={"efficacy": "허가정보 효능"},
            e_drug_result=e_drug,
        )
        self.assertIn("충분한 설명", reply)
        enrich.assert_not_called()
        self.assertIn("e약은요 공식 효능", generate.call_args.kwargs["contents"])
        self.assertNotIn("허가정보 효능", generate.call_args.kwargs["contents"])

    def test_e_drug_timeout_uses_permission_efficacy(self):
        reply, enrich, generate = self._run_permission_general(
            intent="efficacy",
            permission_fields={"efficacy": "허가정보 공식 효능"},
            e_drug_error=TimeoutError("timeout"),
        )
        self.assertIn("충분한 설명", reply)
        enrich.assert_called_once()
        self.assertIn("허가정보 공식 효능", generate.call_args.kwargs["contents"])

    def test_e_drug_empty_uses_permission_dosage(self):
        reply, _, generate = self._run_permission_general(
            intent="dosage",
            permission_fields={"usage": "허가정보 공식 용법용량"},
        )
        self.assertIn("충분한 설명", reply)
        self.assertIn("허가정보 공식 용법용량", generate.call_args.kwargs["contents"])

    def test_e_drug_empty_uses_permission_precautions(self):
        reply, _, generate = self._run_permission_general(
            intent="precautions",
            permission_fields={"cautions": "허가정보 공식 주의사항"},
        )
        self.assertIn("충분한 설명", reply)
        self.assertIn("허가정보 공식 주의사항", generate.call_args.kwargs["contents"])

    def test_e_drug_empty_uses_explicit_permission_side_effects(self):
        reply, _, generate = self._run_permission_general(
            intent="side_effects",
            permission_fields={"side_effects": "공식 이상반응 절"},
        )
        self.assertIn("충분한 설명", reply)
        self.assertIn("공식 이상반응 절", generate.call_args.kwargs["contents"])

    def test_permission_exact_validation_failure_keeps_general_fallback(self):
        reply, _, generate = self._run_permission_general(
            intent="efficacy",
            permission_fields={"efficacy": "다른 제품 효능"},
            permission_verified=False,
        )
        self.assertIn("식약처 공식정보를 확인할 수 없어", reply)
        generate.assert_not_called()

    def test_permission_identity_only_without_requested_field_keeps_fallback(self):
        selected = {"medicine_code": "202400001", "product_name": "공식허가약정"}
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch("app.services.external_api_service.fetch_e_drug_info", return_value=None),
            patch.object(
                gemini_service,
                "_with_official_permission_ingredient",
                return_value={
                    **selected,
                    "ingredient": "공식성분 100mg",
                    "_permission_identity_verified": True,
                },
            ),
            patch.object(gemini_service, "_generate_content_with_retry") as generate,
        ):
            reply = gemini_service.generate_chat_response(
                "효능을 알려줘", user_id="U1", selected_medicine=selected, intent="efficacy"
            )
        self.assertIn("식약처 공식정보를 확인할 수 없어", reply)
        generate.assert_not_called()

    def test_permission_diagnostic_log_excludes_sensitive_content(self):
        official = {
            "medicine_code": "198700430",
            "product_name": "민감한 질문에 포함된 제품명",
            "ingredient": None,
        }
        with (
            patch(
                "app.services.mfds_drug_permission.db.find_permission_product_by_item_seq",
                return_value=None,
            ),
            patch(
                "app.services.mfds_drug_permission.client.fetch_permission_detail",
                side_effect=RuntimeError("SECRET_KEY full response body"),
            ),
            self.assertLogs(gemini_service.logger, level="WARNING") as captured,
        ):
            result = gemini_service._with_official_permission_ingredient(official)

        output = "\n".join(captured.output)
        self.assertIsNone(result["ingredient"])
        self.assertIn("permission_api_failed", output)
        self.assertIn("exception_type=RuntimeError", output)
        self.assertIn("final_ingredient_usable=false", output.casefold())
        self.assertNotIn("SECRET_KEY", output)
        self.assertNotIn("full response body", output)
        self.assertNotIn("민감한 질문", output)

    def test_selected_permission_ingredient_reaches_dur_consultation(self):
        selected = {
            "medicine_code": "198700430",
            "product_name": "알마겔정(알마게이트)(수출명:유한가스트라겔정)",
        }
        e_drug = {**selected, "ingredient": None, "source": "e약은요"}
        enriched = {**e_drug, "ingredient": "알마게이트 500mg"}
        fake_client = MagicMock()
        fake_client.__enter__.return_value = fake_client
        fake_client.__exit__.return_value = False
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch("google.genai.Client", return_value=fake_client),
            patch.object(
                gemini_service,
                "_generate_content_with_retry",
                return_value=SimpleNamespace(parsed={"drug_names": []}),
            ),
            patch(
                "app.services.external_api_service.fetch_e_drug_info",
                return_value=e_drug,
            ),
            patch.object(
                gemini_service,
                "_with_official_permission_ingredient",
                return_value=enriched,
            ),
            patch(
                "app.services.dur_service.analyze_dur_consultation",
                return_value={"status": "current", "items": []},
            ) as analyze,
        ):
            reply = gemini_service.generate_chat_response(
                "같이 먹어도 돼?",
                user_id="U1",
                selected_medicine=selected,
                intent="combination",
            )

        self.assertIn("해당하는 정보를 찾지 못했어요", reply)
        self.assertEqual(
            analyze.call_args.kwargs["selected_medicine"]["ingredient"],
            "알마게이트 500mg",
        )
        self.assertEqual(analyze.call_args.kwargs["risk_types"], {"병용금기"})

    def test_question_intents_and_minimal_official_fields(self):
        self.assertIn("combination", classify_question("A약과 B약 같이 먹어도 돼?"))
        self.assertTrue(is_safety_question(classify_question("임신 중 먹어도 돼?")))
        selected = select_official_context(
            {"medicine_code": "1", "product_name": "약", "ingredient": "성분", "efficacy": "효능", "usage": "용법", "side_effects": "부작용", "source": "e약은요"},
            {"usage"},
        )
        self.assertEqual(selected, {"medicine_code": "1", "product_name": "약", "usage": "용법", "source": "e약은요"})

    def test_explicit_quick_intents_override_natural_language_classification(self):
        cases = {
            "combination": {"병용금기"},
            "age": {"연령금기"},
            "pregnancy": {"임부금기"},
            "duplicate": {"중복성분", "효능군중복"},
        }
        for explicit_intent, expected_risk_types in cases.items():
            with self.subTest(explicit_intent=explicit_intent):
                intents = resolve_question_intents(
                    "이 약 같이 먹어도 돼? 안전한가요?",
                    explicit_intent,
                )
                self.assertEqual(intents, {explicit_intent})
                self.assertEqual(
                    set().union(
                        *(
                            chat_context_service.DUR_TYPES_BY_INTENT.get(
                                intent,
                                set(),
                            )
                            for intent in intents
                        )
                    ),
                    expected_risk_types,
                )

    def test_free_text_keeps_existing_question_classification(self):
        self.assertEqual(
            resolve_question_intents("이 약 같이 먹어도 돼?"),
            classify_question("이 약 같이 먹어도 돼?"),
        )

    def test_explicit_edrug_intents_select_only_requested_fields(self):
        official = {
            "medicine_code": "1",
            "product_name": "약",
            "efficacy": "효능",
            "usage": "용법",
            "cautions": "주의",
            "side_effects": "부작용",
            "source": "e약은요",
        }
        expected_fields = {
            "efficacy": "efficacy",
            "dosage": "usage",
            "precautions": "cautions",
            "side_effects": "side_effects",
        }
        for intent, field in expected_fields.items():
            with self.subTest(intent=intent):
                selected = select_official_context(official, {intent})
                self.assertIn(field, selected)
                self.assertFalse(is_safety_question({intent}))

    def test_current_accepts_reordered_multiset(self):
        conn = _database(current=["성분A", "성분B", "성분A"], analyzed=["성분A", " 성분a ", "성분B"])
        with patch.object(chat_context_service, "get_connection", return_value=conn):
            result = load_latest_dur_context("U1", {"combination"})
        self.assertEqual(result["status"], "current")

    def test_changed_medicines_are_stale_and_matches_are_blocked(self):
        matches = [{"type": "병용금기", "ingredient_a": "과거A", "ingredient_b": "과거B", "reason": "과거 결과"}]
        conn = _database(current=["현재성분"], analyzed=["과거A", "과거B"], matches=matches)
        with patch.object(chat_context_service, "get_connection", return_value=conn):
            result = load_latest_dur_context("U1", {"combination"})
        self.assertEqual(result, {"status": "stale", "items": []})

    def test_missing_and_not_required(self):
        conn = _database(current=["성분A"], include_result=False)
        with patch.object(chat_context_service, "get_connection", return_value=conn):
            missing = load_latest_dur_context("U1", {"combination"})
        self.assertEqual(missing, {"status": "missing", "items": []})
        self.assertEqual(load_latest_dur_context("U1", {"efficacy"}), {"status": "not_required", "items": []})
        self.assertEqual(load_latest_dur_context("", {"combination"}), {"status": "missing", "items": []})

    def test_prompt_keeps_safety_rules_and_excludes_raw_json(self):
        prompt_text = build_grounded_chat_prompt(message="같이 먹어도 돼?", intents={"combination"}, official_contexts=[], dur_result={"status": "stale", "items": []})
        self.assertIn("DUR 위험 여부를 새로 추론하거나 판정하지 마세요", prompt_text)
        self.assertIn("서버가 전달한 DUR 분석 결과만 설명하세요", prompt_text)
        self.assertIn("핵심 답을 첫 문장에", prompt_text)
        self.assertIn("근거가 있는 경우에만", prompt_text)
        self.assertIn("stale", prompt_text)
        self.assertNotIn("raw_json", prompt_text)

    def test_prompt_requires_plain_language_without_dropping_exact_medicine_terms(self):
        prompt_text = build_grounded_chat_prompt(
            message="이 약이 어떤 약인지 알려줘",
            intents={"efficacy"},
            official_contexts=[],
            dur_result={"status": "not_required", "items": []},
        )
        examples = {
            "융모": "장의 구조를 뜻하는 문맥에서만",
            "상피": "몸 표면이나 장기를 덮는 얇은 층",
            "수용체": "약 성분이 작용하는 몸속 부분",
            "대사": "약을 처리하는 문맥에서만",
            "흡수": "약 성분이 몸 안으로 들어오는 과정",
            "배설": "몸 밖으로 내보내는 과정",
            "분비": "몸에서 특정 물질을 만들어 내보내는 과정",
            "효소": "몸속에서 화학 작용을 돕는 물질",
        }
        for term, explanation in examples.items():
            with self.subTest(term=term):
                self.assertIn(term, prompt_text)
                self.assertIn(explanation, prompt_text)
        self.assertIn("전문용어를 괄호 안에 덧붙이지 마세요", prompt_text)
        self.assertIn("주성분, 복용량, 공식 의약품명·제품명·성분명은 원래 표현을 유지", prompt_text)
        self.assertIn("추측하지 말고", prompt_text)
        self.assertIn("의료적 판단을 단정하지 마세요", prompt_text)

    def test_prompt_preserves_source_conditions_and_personal_prescription_boundary(self):
        fixtures = {
            "efficacy": {"efficacy": "합성 증상 완화"},
            "dosage": {"dosage": "18세 이상, 1회 2mg, 하루 1회, 3일간 주사"},
            "precautions": {"precautions": "12세 미만은 사용하면 안 됨. 예외: 공식 조건 충족 시"},
            "side_effects": {"side_effects": "심각한 증상이 나타날 수 있음"},
            "general": {},
        }
        rules = (
            "목록에 없는 어려운 말에도 같은 원칙",
            "단순 단어 치환은 하지 마세요",
            "용량, 단위, 횟수, 기간, 연령 조건과 적용 대상, 금지·주의·예외 조건의 강도를 그대로 유지",
            '"사용하면 안 됨"을 "주의가 필요함"으로 완화하지 마세요',
            '심각한 위험이나 증상을 단순한 "불편함"으로 축소하지 마세요',
            "투여를 모든 경우에 복용으로 바꾸지 마세요",
            "먹는 약·주사·바르는 약 등 공식 자료에 나온 사용 방식을 유지",
            "설명이 어렵다는 이유로 공식 자료가 없다고 답하지 마세요",
            "공식 자료의 일반 사용법은 일반 안내임을 분명히",
            "실제 등록 처방 정보가 제공된 경우에만",
            "개인 처방 정보 없이 개인 복용량을 새로 정하지 말고",
            "일반 사용법을 개인 처방처럼 표현하지 마세요",
            "공식정보에 없는 내용을 사실처럼 만들지 마세요",
            "복용 시작, 중단, 용량 변경을 지시하지 마세요",
            "핵심 답을 첫 문장에",
        )
        for intent, source in fixtures.items():
            with self.subTest(intent=intent):
                prompt = build_grounded_chat_prompt(
                    message="합성 질문", intents={intent},
                    official_contexts=[source] if source else [],
                    dur_result={"status": "not_required", "items": []},
                )
                for rule in rules:
                    self.assertIn(rule, prompt)
                for value in source.values():
                    self.assertIn(value, prompt)

    def test_fixed_replies_preserve_missing_stale_and_zero_result_meanings(self):
        for intent in ("combination", "age", "pregnancy", "duplicate"):
            with self.subTest(intent=intent):
                missing = gemini_service._dur_context_unavailable_reply({intent}, "missing")
                stale = gemini_service._dur_context_unavailable_reply({intent}, "stale")
                zero = gemini_service._dur_no_match_reply({intent})
                self.assertIn("확인한 결과를 찾지 못했어요", missing)
                self.assertNotIn("복용 중인 약이 바뀌어", missing)
                self.assertIn("복용 중인 약이 바뀌어", stale)
                self.assertIn("이전 결과를 그대로 사용하기 어려워요", stale)
                self.assertIn("찾지 못했어요", zero)
                self.assertNotIn("다시 시도", zero)
                for reply in (missing, stale, zero):
                    for jargon in ("DUR", "병용금기", "연령금기", "임부금기", "효능군중복"):
                        self.assertNotIn(jargon, reply)
                    self.assertNotIn("안전합니다", reply)
                    self.assertNotIn("복용해도 됩니다", reply)

    def test_general_conversation_rules_do_not_match_drug_questions(self):
        self.assertIn("안녕하세요", general_conversation_reply("안녕하세요"))
        self.assertIn("도움이 되어", general_conversation_reply("고마워"))
        self.assertIn("e약은요", general_conversation_reply("무슨 기능이 있어?"))
        self.assertIsNone(general_conversation_reply("이 약 같이 먹어도 돼?"))

    def test_general_rules_bypass_gemini_and_safety_fallback_remains(self):
        with patch.object(gemini_service, "GEMINI_API_KEY", None):
            greeting = gemini_service.generate_chat_response("안녕", user_id="U1")
            safety = gemini_service.generate_chat_response("같이 먹어도 돼?", user_id="U1")
        self.assertIn("안녕하세요", greeting)
        self.assertIn("현재 복용약으로 다시 확인", safety)
        self.assertNotIn("타이레놀", safety)

        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch.object(gemini_service, "_generate_content_with_retry") as generate,
        ):
            reply = gemini_service.generate_chat_response("감사합니다", user_id="U1")
        self.assertIn("도움이 되어", reply)
        generate.assert_not_called()

    def test_chat_http_exception_is_not_converted_to_generic_reply(self):
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch("google.genai.Client"),
            patch.object(
                gemini_service,
                "_generate_content_with_retry",
                side_effect=HTTPException(status_code=404, detail="사용자가 없습니다."),
            ),
        ):
            with self.assertRaises(HTTPException) as raised:
                gemini_service.generate_chat_response("약 질문", user_id="missing")
        self.assertEqual(raised.exception.status_code, 404)

    def test_chat_general_exception_keeps_generic_fallback(self):
        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch("google.genai.Client"),
            patch.object(
                gemini_service,
                "_generate_content_with_retry",
                side_effect=RuntimeError("temporary failure"),
            ),
        ):
            reply = gemini_service.generate_chat_response("약 질문", user_id="U1")
        self.assertIn("정보를 불러오는 중 문제가 발생했습니다", reply)


if __name__ == "__main__":
    unittest.main()
