from unittest.mock import patch
from types import SimpleNamespace
from fastapi import FastAPI
from fastapi.testclient import TestClient
from app.routes.drug_explain import router
from app.services.pharmacist.conversation import conversation_context, dialogue_prompt, record_evidence, resolve_followup

A = {"medicine_code": "202400001", "product_name": "첫약정"}
B = {"medicine_code": "202400002", "product_name": "둘약정"}


def history(medicines=None, content="첫약정에 음주 주의가 있어요.", intent="precautions"):
    return [{"role": "user", "content": "주의할 점은?", "intent": intent},
            {"role": "assistant", "content": content, "medicines": medicines or [A]}]


def test_followup_single_and_reset():
    result = resolve_followup("그럼 술은?", None, history(), None, [])
    assert result[2] == A and "첫약정" in result[0] and result[4] is None
    assert resolve_followup("그럼 술은?", None, [], B, [])[2] == B


def test_ordinal_uses_answer_order_and_does_not_guess():
    previous = history([A, B], "둘약정: 주의하세요. 첫약정: 주의하세요.")
    result = resolve_followup("두 번째 약은?", None, previous, None, [A, B])
    assert result[2] == A and result[3] == []
    assert "둘약정" not in result[0]
    assert resolve_followup("세 번째 약은?", None, previous, None, [A, B])[4]
    assert resolve_followup("그럼 술은?", None, previous, None, [A, B])[4]


def test_summary_keeps_query_scope_but_rechecks_evidence():
    result = resolve_followup("짧게 요약해줘", None, history(intent="health_precautions"), None, [])
    assert result[1] == "health_precautions" and result[2] == A
    with conversation_context(history()) as evidence:
        assert "공식 근거가 아니며" in dialogue_prompt()
        assert evidence["sources"] == []  # History alone is not a source.


def test_evidence_is_request_local_and_only_official_labels():
    with conversation_context([]) as first:
        record_evidence([{**A, "source": "e약은요 + 식약처 의약품 제품 허가정보"}])
        record_evidence([{**A, "source": "모델의 지식"}])
        assert first["sources"] == ["식약처 의약품 허가정보", "식약처 e약은요"]
        assert first["medicines"] == [A]
        with conversation_context([]) as second:
            assert second["sources"] == []
        assert first["sources"]
    with conversation_context([]) as other:
        assert other["sources"] == []


def test_route_only_displays_new_verified_sources():
    app = FastAPI()
    app.include_router(router)
    client = TestClient(app)
    payload = {"user_id": "synthetic", "message": "그럼 술은?", "recent_history": history()}
    def generated(*args, **kwargs):
        assert kwargs["selected_medicine"] == A
        assert dialogue_prompt()
        record_evidence([{**A, "source": "e약은요"}])
        return "첫약정에 음주 관련 주의가 있어요."
    with patch("app.services.gemini_service.generate_chat_response", side_effect=generated):
        result = client.post("/api/v1/drug-explain/chat", json=payload)
    assert result.status_code == 200
    assert result.json()["sources"] == ["식약처 e약은요"]
    assert result.json()["conversation_medicines"] == [A]
    with patch("app.services.gemini_service.generate_chat_response", return_value="조회하지 못했어요."):
        assert client.post("/api/v1/drug-explain/chat", json=payload).json()["sources"] == []
    payload["recent_history"] = history([A, B], "첫약정 둘약정")
    with patch("app.services.gemini_service.generate_chat_response") as generate:
        result = client.post("/api/v1/drug-explain/chat", json=payload)
        assert "어떤 약" in result.json()["reply"]
        generate.assert_not_called()


def test_history_bound_is_enforced_and_old_client_supported():
    app = FastAPI()
    app.include_router(router)
    client = TestClient(app)
    payload = {"user_id": "synthetic", "message": "안녕하세요"}
    with patch("app.services.gemini_service.generate_chat_response", return_value="안녕하세요."):
        assert client.post("/api/v1/drug-explain/chat", json=payload).status_code == 200
    payload["recent_history"] = [{"role": "user", "content": "질문"}] * 7
    assert client.post("/api/v1/drug-explain/chat", json=payload).status_code == 422


def test_actual_generated_answer_attaches_source_only_after_success():
    from app.services import gemini_service as gemini
    official = {**A, "source": "e약은요", "cautions": "음주 시 주의한다."}
    previous = history()
    with (
        patch.object(gemini, "GEMINI_API_KEY", "synthetic-key"),
        patch("google.genai.Client"),
        patch.object(gemini, "_generate_content_with_retry", return_value=SimpleNamespace(parsed={"drug_names": []})),
        patch("app.services.external_api_service.fetch_e_drug_info", return_value=official),
        patch("app.services.chat_context_service.load_latest_dur_context", return_value={"status": "not_required", "items": []}),
        patch.object(gemini, "_generate_complete_chat_reply", return_value="첫약정은 음주 시 주의하세요.") as generate,
        conversation_context(previous) as evidence,
    ):
        gemini.generate_chat_response("술은?", selected_medicine=A, intent="precautions")
        assert evidence["sources"] == ["식약처 e약은요"]
        assert "최근 대화" in generate.call_args.kwargs["prompt"]
        with conversation_context(previous) as failed:
            generate.return_value = gemini.INCOMPLETE_CHAT_REPLY
            gemini.generate_chat_response("술은?", selected_medicine=A, intent="precautions")
            assert failed["sources"] == []


def test_health_followup_preserves_personal_question_intent():
    result = resolve_followup("그럼 술은?", None, history(intent="health_precautions"), None, [])
    assert result[1] == "health_precautions"


def test_summary_after_ordinal_stays_on_last_explained_medicine():
    previous = history([A], "첫약정: 주의하세요.")
    result = resolve_followup("짧게 요약해줘", None, previous, None, [A, B])
    assert result[2] == A and result[3] == []
    result = resolve_followup("그럼 둘약정은?", None, history([A, B], "첫약정 둘약정"), None, [A, B])
    assert result[2] == B and result[4] is None


def test_all_health_summary_reloads_full_scope_not_first_twenty():
    previous = history([A, B], "첫약정 둘약정", intent="health_precautions")
    previous[0]["scope"] = "all"
    result = resolve_followup("짧게 요약해줘", None, previous, None, [])
    assert result[2] is None and result[3] == []
    assert result[1] == "health_precautions"
