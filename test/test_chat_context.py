import json
import sqlite3
import unittest
from unittest.mock import patch

from app.services import chat_context_service, gemini_service
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
