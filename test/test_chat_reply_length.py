"""Final answer budget: summarization, not truncation or silent rejection."""
import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.services import gemini_service as service


def _chat_response(text, *, finish_reason="STOP"):
    return SimpleNamespace(text=text, candidates=[SimpleNamespace(
        finish_reason=finish_reason,
        content=SimpleNamespace(parts=[SimpleNamespace(text=text)]),
    )], usage_metadata=None)


class ChatReplyLengthTest(unittest.TestCase):
    def test_short_and_boundary_replies_are_unchanged(self):
        for reply in ("확인하지 못했어요.", "가" * 599 + "."):
            with self.subTest(length=len(reply)), patch.object(
                service, "_generate_chat_response", return_value=reply
            ), patch.object(service, "_generate_content_with_retry") as generate:
                self.assertEqual(service.generate_chat_response("질문"), reply)
                generate.assert_not_called()

    def test_accepted_long_reply_is_summarized_with_original_conditions(self):
        source = "가나다정은 1회 2 mg, 1일 3회이며 18세 미만은 사용하지 마세요. " + "반복 설명. " * 100
        summary = "가나다정은 1회 2 mg, 1일 3회이며 18세 미만은 사용하지 마세요."
        with patch.object(service, "_generate_content_with_retry", side_effect=[
            _chat_response(summary), _chat_response('{"preserved":true}')
        ]) as generate:
            result = service._summarize_chat_reply(MagicMock(), source, medicine_names=("가나다정",))
        self.assertEqual(result, summary)
        self.assertIn(source, generate.call_args_list[0].kwargs["contents"])
        self.assertEqual(generate.call_args_list[0].kwargs["config"]["max_output_tokens"], 2048)

    def test_overlong_summary_retries_from_original(self):
        source = "원문. " * 200
        with patch.object(service, "_generate_content_with_retry", side_effect=[
            _chat_response("긴 설명. " * 200), _chat_response("핵심 안내예요."),
            _chat_response('{"preserved":true}')
        ]) as generate:
            result = service._summarize_chat_reply(MagicMock(), source)
        self.assertEqual(result, "핵심 안내예요.")
        self.assertIn(source.strip(), generate.call_args_list[1].kwargs["contents"])

    def test_accepted_generation_flows_to_summary_without_length_rejection(self):
        source = "약마다 사용법이 달라요. " * 80
        with patch("google.genai.Client"), patch.object(service, "_generate_chat_response", side_effect=lambda *a, **k:
                service._generate_complete_chat_reply(MagicMock(), prompt="일반 질문", max_output_tokens=1024)), \
                patch.object(service, "_generate_content_with_retry", side_effect=[
                    _chat_response(source), _chat_response("약마다 사용법이 달라요."),
                    _chat_response('{"preserved":true}')
                ]) as generate:
            reply = service.generate_chat_response("약 사용법")
        self.assertEqual(reply, "약마다 사용법이 달라요.")
        self.assertEqual(generate.call_count, 3)
        self.assertEqual(generate.call_args_list[0].kwargs["config"]["max_output_tokens"], 1024)
        self.assertIn(source.strip(), generate.call_args_list[1].kwargs["contents"])

    def test_production_length_misses_keep_compressing_instead_of_notice(self):
        source = "가" * 735 + "."
        summaries = ["나" * 663 + ".", "다" * 667 + ".", "라" * 549 + "."]
        with patch.object(service, "_generate_content_with_retry", side_effect=[
            *[_chat_response(text) for text in summaries],
            _chat_response('{"preserved":true}'),
        ]) as generate:
            result = service._summarize_chat_reply(MagicMock(), source)
        self.assertEqual(result, summaries[-1])
        self.assertLessEqual(len(result), 600)
        second_prompt = generate.call_args_list[1].kwargs["contents"]
        third_prompt = generate.call_args_list[2].kwargs["contents"]
        self.assertIn("실제 길이는 664자", second_prompt)
        self.assertIn("목표는 340자", second_prompt)
        self.assertIn(summaries[0], second_prompt)
        self.assertIn("실제 길이는 668자", third_prompt)
        self.assertIn("목표는 260자", third_prompt)
        self.assertIn(source, third_prompt)

    def test_fourth_compression_can_return_useful_reply(self):
        source = "가" * 735 + "."
        with patch.object(service, "_generate_content_with_retry", side_effect=[
            *[_chat_response("나" * 650 + ".") for _ in range(3)],
            _chat_response("약마다 주의사항이 달라요."),
            _chat_response('{"preserved":true}'),
        ]):
            self.assertEqual(service._summarize_chat_reply(MagicMock(), source), "약마다 주의사항이 달라요.")

    def test_missing_numbers_or_medicine_does_not_pass(self):
        source = "가나다정은 18세 미만에게 사용하지 마세요. " + "설명. " * 200
        with patch.object(service, "_generate_content_with_retry", side_effect=[
            _chat_response("가나다정은 주의하세요."), _chat_response("18세 미만은 주의하세요.")
        ]):
            result = service._summarize_chat_reply(MagicMock(), source, medicine_names=("가나다정",))
        self.assertEqual(result, source)

    def test_semantic_loss_or_added_safety_is_rejected(self):
        # Covers dropped warnings, exceptions, unresolved targets and false zero conclusions.
        source = "함께 사용하면 안 돼요. 임신 중은 예외 없이 금기예요. 일부 약은 확인하지 못했어요. " + "설명. " * 200
        for summary in ("함께 사용해도 돼요.", "금기는 없어요.", "임신 중에는 주의하세요."):
            with self.subTest(summary=summary), patch.object(service, "_generate_content_with_retry", side_effect=[
                _chat_response(summary), _chat_response('{"preserved":false}'),
                _chat_response(summary), _chat_response('{"preserved":false}')
            ]):
                self.assertEqual(service._summarize_chat_reply(MagicMock(), source), source)

    def test_summary_failures_retain_original_answer(self):
        source = "설명. " * 200
        for responses in (
            [TimeoutError(), TimeoutError()],
            [_chat_response(""), _chat_response("")],
            [_chat_response("안내예요.", finish_reason="MAX_TOKENS")] * 2,
            [_chat_response("안내예요."), _chat_response("not json")] * 2,
        ):
            with self.subTest(responses=responses), patch.object(service, "_generate_content_with_retry", side_effect=responses):
                reply = service._summarize_chat_reply(MagicMock(), source)
                self.assertTrue(reply)
                self.assertEqual(reply, source)

    def test_all_length_attempts_exhausted_retain_original(self):
        source = "원문 답변. " * 150
        with patch.object(service, "_generate_content_with_retry", side_effect=[
            _chat_response("요약 초과. " * 150) for _ in range(4)
        ]):
            self.assertEqual(service._summarize_chat_reply(MagicMock(), source), source)

    def test_summary_client_failure_retains_accepted_answer(self):
        source = "확인된 약의 주의사항이에요. " * 80
        with patch.object(service, "_generate_chat_response", return_value=source), \
                patch("google.genai.Client", side_effect=RuntimeError("unavailable")):
            self.assertEqual(service.generate_chat_response("질문"), source)

    def test_all_response_modes_pass_through_finalizer(self):
        for kwargs in ({}, {"selected_medicine": {"name": "가나다정"}},
                       {"selected_medicines": [{"name": "가나다정"}, {"name": "라마바정"}]},
                       {"intent": "combination"}):
            with self.subTest(kwargs=kwargs), patch.object(service, "_generate_chat_response", return_value="설명. " * 200), \
                    patch("google.genai.Client"), patch.object(service, "_summarize_chat_reply", return_value="요약 안내예요.") as summarize:
                self.assertEqual(service.generate_chat_response("질문", **kwargs), "요약 안내예요.")
                summarize.assert_called_once()


if __name__ == "__main__":
    unittest.main()
