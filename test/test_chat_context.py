import unittest
from unittest.mock import patch

from app.services import gemini_service
from app.services.chat_context_service import (
    build_grounded_chat_prompt,
    classify_question,
    is_safety_question,
    select_official_context,
)


class ChatContextTest(unittest.TestCase):
    def test_question_intents_cover_supported_grounding(self):
        cases = {
            "이 약이 뭐야?": "overview",
            "이 약 효능이 뭐야?": "efficacy",
            "어떻게 먹어?": "usage",
            "주의사항 알려줘": "precautions",
            "부작용이 뭐야?": "side_effects",
            "다른 약과 상호작용 있어?": "interaction",
            "A약과 B약 같이 먹어도 돼?": "combination",
            "이 약은 내 나이에 먹어도 돼?": "age",
            "임신 중 먹어도 돼?": "pregnancy",
            "비슷한 효과의 약을 중복해서 먹고 있어?": "duplicate",
            "이 약 복용해도 안전해?": "safety",
        }
        for question, expected in cases.items():
            with self.subTest(question=question):
                self.assertIn(expected, classify_question(question))

    def test_safety_intents_are_recognized(self):
        for question in (
            "같이 먹어도 돼?",
            "내 나이에 먹어도 돼?",
            "임신 중 먹어도 돼?",
            "효능군 중복이야?",
        ):
            self.assertTrue(is_safety_question(classify_question(question)))

    def test_official_context_only_contains_intent_fields(self):
        official = {
            "medicine_code": "123",
            "product_name": "테스트약",
            "ingredient": "테스트성분",
            "manufacturer": "테스트제약",
            "efficacy": "효능",
            "usage": "복용법",
            "cautions": "주의",
            "interaction": "상호작용",
            "side_effects": "부작용",
            "storage": "보관",
            "image_url": "https://example.test/image.png",
            "source": "e약은요",
        }
        selected = select_official_context(official, {"usage"})
        self.assertEqual(
            selected,
            {
                "medicine_code": "123",
                "product_name": "테스트약",
                "usage": "복용법",
                "source": "e약은요",
            },
        )

    def test_prompt_forbids_llm_dur_judgment(self):
        prompt = build_grounded_chat_prompt(
            message="같이 먹어도 돼?",
            intents={"combination"},
            official_contexts=[],
            dur_contexts=[
                {
                    "analysis_type": "병용금기",
                    "ingredient_a": "A",
                    "ingredient_b": "B",
                    "prohibition_or_caution": "함께 사용하지 않음",
                }
            ],
        )
        self.assertIn("DUR 위험 여부를 새로 추론하거나 판정하지 마세요", prompt)
        self.assertIn("서버가 전달한 DUR 분석 결과만 설명하세요", prompt)
        self.assertNotIn("raw_json", prompt)

    def test_safety_question_without_api_key_does_not_use_demo_knowledge(self):
        with patch.object(gemini_service, "GEMINI_API_KEY", None):
            reply = gemini_service.generate_chat_response(
                "A약과 B약 같이 먹어도 돼?",
                user_id="test-user",
            )
        self.assertIn("현재 확인된 식약처 정보만으로는 확인하기 어렵습니다", reply)
        self.assertNotIn("타이레놀", reply)


if __name__ == "__main__":
    unittest.main()
