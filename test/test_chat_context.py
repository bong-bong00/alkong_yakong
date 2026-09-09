import json
import os
import sqlite3
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.services import chat_context_service, gemini_service
from app.services.mfds_drug_permission import client as permission_client
from app.services.mfds_drug_permission import db as permission_db
from app.services.chat_context_service import (
    build_grounded_chat_prompt,
    classify_question,
    general_conversation_reply,
    is_safety_question,
    load_latest_dur_context,
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
            )

        self.assertIn("확인되지 않았습니다", reply)
        self.assertEqual(
            analyze.call_args.kwargs["selected_medicine"]["ingredient"],
            "알마게이트 500mg",
        )

    def test_question_intents_and_minimal_official_fields(self):
        self.assertIn("combination", classify_question("A약과 B약 같이 먹어도 돼?"))
        self.assertTrue(is_safety_question(classify_question("임신 중 먹어도 돼?")))
        selected = select_official_context(
            {"medicine_code": "1", "product_name": "약", "ingredient": "성분", "efficacy": "효능", "usage": "용법", "side_effects": "부작용", "source": "e약은요"},
            {"usage"},
        )
        self.assertEqual(selected, {"medicine_code": "1", "product_name": "약", "usage": "용법", "source": "e약은요"})

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
        self.assertIn("stale", prompt_text)
        self.assertNotIn("raw_json", prompt_text)

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
        self.assertIn("DUR 재분석", safety)
        self.assertNotIn("타이레놀", safety)

        with (
            patch.object(gemini_service, "GEMINI_API_KEY", "configured"),
            patch.object(gemini_service, "_generate_content_with_retry") as generate,
        ):
            reply = gemini_service.generate_chat_response("감사합니다", user_id="U1")
        self.assertIn("도움이 되어", reply)
        generate.assert_not_called()


if __name__ == "__main__":
    unittest.main()
