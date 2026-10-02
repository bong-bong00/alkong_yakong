"""Off-topic selection/history must not trigger official lookups or generation."""
from unittest.mock import patch

import pytest

from app.services import gemini_service
from app.services.chat_context_service import (
    AMBIGUOUS_QUESTION_REPLY,
    UNRELATED_QUESTION_REPLY,
    classify_question_scope,
)
from app.services.pharmacist.conversation import resolve_followup

A = {"medicine_code": "202400001", "product_name": "첫약정"}
B = {"medicine_code": "202400002", "product_name": "둘약정"}


@pytest.mark.parametrize("scope", [
    {}, {"selected_medicine": A}, {"selected_medicines": [A, B]},
    {"selected_medicine": A, "intent": "health_precautions"},
])
@pytest.mark.parametrize("message", ["오늘 날씨 어때?", "맛집 추천해줘", "그럼 축구는?"])
def test_unrelated_question_never_looks_up_or_generates(scope, message):
    with (
        patch("app.services.external_api_service.fetch_e_drug_info") as official,
        patch("app.services.medication_feature_dur_client.load_remote_current_medicines") as medicines,
        patch("app.services.pharmacist.health_precautions.generate_health_reply") as health,
        patch.object(gemini_service, "_generate_content_with_retry") as generate,
    ):
        assert gemini_service.generate_chat_response(message, **scope) == UNRELATED_QUESTION_REPLY
        for mock in (official, medicines, health, generate):
            mock.assert_not_called()


@pytest.mark.parametrize("scope", [{"selected_medicine": A}, {"selected_medicines": [A, B]}])
@pytest.mark.parametrize("message", ["ㅋㅋㅋㅋ", "???", "오늘 뭐하지?"])
def test_ambiguous_selected_question_requests_clarification(scope, message):
    assert gemini_service.generate_chat_response(message, **scope) == AMBIGUOUS_QUESTION_REPLY


@pytest.mark.parametrize("message", ["그럼 술은?", "알코올은?", "효과는?", "짧게 요약해줘"])
def test_short_selected_medication_questions_remain_allowed(message):
    assert classify_question_scope(message, has_medicine_context=True) in {
        "medicine_specific", "general_medication",
    }


def test_medication_question_with_weather_word_is_not_blocked():
    assert classify_question_scope("비 오는 날 약 보관은 어떻게 하나요?") == "general_medication"


@pytest.mark.parametrize("medicines", [[A], [A, B]])
def test_off_topic_followup_is_checked_before_history_resolution(medicines):
    history = [
        {"role": "user", "content": "주의할 점은?", "intent": "precautions"},
        {"role": "assistant", "content": "첫약정 둘약정", "medicines": medicines},
    ]
    unrelated = resolve_followup("그럼 날씨는?", None, history, None, [])
    assert unrelated[0] == "그럼 날씨는?"
    assert unrelated[4] == UNRELATED_QUESTION_REPLY
    if len(medicines) == 1:
        relevant = resolve_followup("그럼 술은?", None, history, None, [])
        assert relevant[2] == A and relevant[4] is None
