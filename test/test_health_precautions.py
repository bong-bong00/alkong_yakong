import json
import sqlite3
from unittest.mock import MagicMock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.models.schemas import DrugExplainChatRequest
from app.routes.drug_explain import router
from app.services import gemini_service as gemini
from app.services.pharmacist import health_precautions as health


MEDICINE = {"medicine_code": "123456789", "product_name": "확인약정"}
SECOND = {"medicine_code": "987654321", "product_name": "다른약정"}


def test_health_highlights_use_saved_facts_and_lifestyle_aliases(context):
    terms = health.health_highlight_terms(
        "health-user", "고혈압이 있으면 주의하세요. 술과 알코올을 피하세요. "
        "흡연 및 담배, 니코틴에 주의하세요. 페니실린 알레르기에 주의하세요. "
        "당뇨 환자에 대한 안내도 있어요.",
    )
    assert {"고혈압", "술", "알코올", "흡연", "담배", "니코틴", "페니실린", "알레르기"} <= set(terms)
    assert "당뇨" not in terms  # Family history is not the user's diagnosis.


def test_health_highlights_do_not_emphasize_missing_information(context):
    assert health.health_highlight_terms(
        "health-user", "알레르기나 흡연·음주 정보를 확인할 수 없어 설명하기 어려워요.",
    ) == []
    assert health.health_highlight_terms("missing", "음주에 주의하세요.") == []
    assert "술" not in health.health_highlight_terms("health-user", "수술 전에 상담하세요.")


@pytest.fixture
def context(tmp_path, monkeypatch):
    path = tmp_path / "health.db"
    conn = sqlite3.connect(path)
    conn.execute("""CREATE TABLE users (
        id TEXT, diseases TEXT, past_illnesses TEXT, allergies TEXT,
        family_illnesses TEXT, smoking TEXT, drinking TEXT,
        past_history INTEGER, family_history INTEGER, password_hash TEXT)""")
    conn.execute("INSERT INTO users VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", (
        "health-user", '["고혈압"]', '["뇌졸중"]', '["페니실린"]', '["당뇨"]',
        "폈어요", "가끔 마셔요", 1, 1, "NEVER_SHARE",
    ))
    conn.execute("INSERT INTO users (id, diseases) VALUES ('other-user', '[\"암\"]')")
    conn.commit()
    conn.close()

    def connect():
        db = sqlite3.connect(path)
        db.row_factory = sqlite3.Row
        return db

    monkeypatch.setattr(health, "get_connection", connect)
    monkeypatch.setattr(gemini, "GEMINI_API_KEY", "")
    monkeypatch.setattr(health, "_official_cautions", lambda medicine: {
        "product_name": medicine["product_name"],
        "cautions": "고혈압 환자는 사용 전 상담한다.\n음주 시에는 사용하지 않는다.",
    })
    return path


def ask(**kwargs):
    return gemini.generate_chat_response(
        "내 건강 상태에서 이 약을 먹을 때 주의할 점은?",
        user_id="health-user", intent="health_precautions", **kwargs,
    )


def test_saved_profile_is_read_for_only_requested_user(context):
    profile = health.load_health_profile("health-user")
    assert profile["diseases"] == ["고혈압"]
    assert profile["past_illnesses"] == ["뇌졸중"]
    assert profile["family_illnesses"] == ["당뇨"]
    assert profile["allergies"] == ["페니실린"]
    assert profile["smoking"] == "폈어요"
    assert profile["drinking"] == "가끔 마셔요"
    assert "password_hash" not in profile and "id" not in profile
    assert health.load_health_profile("other-user")["diseases"] == ["암"]
    assert health.load_health_profile("missing") is None


def test_single_selection_does_not_load_all_medicines_or_mark_incomplete(context, monkeypatch):
    remote = MagicMock(side_effect=AssertionError("must not load all medicines"))
    monkeypatch.setattr("app.services.medication_feature_dur_client.load_remote_current_medicines", remote)
    result = ask(selected_medicine=MEDICINE)
    assert "확인약정" in result and "高" not in result
    assert "고혈압" in result and "일부 약의 공식" not in result
    assert health.CONSULT in result and len(result) <= 600
    remote.assert_not_called()


def test_multiple_scope_preserves_every_selected_medicine(context, monkeypatch):
    seen = []
    def lookup(medicine):
        seen.append(medicine)
        return {"product_name": medicine["product_name"], "cautions": "음주 시에는 사용하지 않는다."}
    monkeypatch.setattr(health, "_official_cautions", lookup)
    result = ask(selected_medicines=[MEDICINE, SECOND])
    assert seen == [MEDICINE, SECOND]
    assert "확인약정" in result and "다른약정" in result and "음주" in result


def test_legacy_first_selection_cannot_hide_other_health_selections(context, monkeypatch):
    third = {"medicine_code": "200403137", "product_name": "세번째약정"}
    medicines = [MEDICINE, SECOND, third]
    seen = []

    def lookup(medicine):
        seen.append(medicine)
        return {**medicine, "source": "식약처 의약품 허가정보",
                "cautions": "음주 시에는 사용하지 않는다."}

    monkeypatch.setattr(health, "_official_cautions", lookup)
    result = ask(selected_medicine=MEDICINE, selected_medicines=medicines)
    assert seen == medicines
    assert all(item["product_name"] in result for item in medicines)

    seen.clear()
    api = FastAPI()
    api.include_router(router)
    response = TestClient(api).post("/api/v1/drug-explain/chat", json={
        "user_id": "health-user", "message": "내 건강 상태에서 주의할 점은?",
        "intent": "health_precautions", "selected_medicine": MEDICINE,
        "selected_medicines": medicines,
    })
    assert response.status_code == 200
    assert seen == medicines
    assert response.json()["conversation_medicines"] == medicines
    assert all(item["product_name"] in response.json()["reply"] for item in medicines)


def test_all_scope_uses_team_medicine_service_and_temporary_selection(context, monkeypatch):
    remote = MagicMock(return_value={"status": "current", "items": [MEDICINE]})
    monkeypatch.setattr("app.services.medication_feature_dur_client.load_remote_current_medicines", remote)
    result = ask(temporary_medicines=[SECOND])
    remote.assert_called_once_with(user_id="health-user")
    assert "확인약정" in result and "다른약정" in result


def test_partial_lookup_retains_known_warning(context, monkeypatch):
    monkeypatch.setattr(health, "_official_cautions", lambda medicine: (
        {"product_name": "확인약정", "cautions": "고혈압 환자는 사용 전 상담한다."}
        if medicine == MEDICINE else None
    ))
    result = ask(selected_medicines=[MEDICINE, SECOND])
    assert "일부 약의 공식 주의사항을 확인하지 못했어요" in result
    assert "고혈압" in result and "확인약정" in result


def test_all_official_lookups_failed_is_not_no_matching_information(context, monkeypatch):
    monkeypatch.setattr(health, "_official_cautions", lambda medicine: None)
    result = ask(selected_medicine=MEDICINE)
    assert "공식 주의사항을 불러오지 못했어요" in result
    assert "직접 연결되는" not in result


def test_no_official_matches_is_not_safe_verdict(context, monkeypatch):
    monkeypatch.setattr(health, "_official_cautions", lambda medicine: {
        "product_name": medicine["product_name"], "cautions": "빛을 피하여 보관한다.",
    })
    result = ask(selected_medicine=MEDICINE)
    assert "직접 연결되는 공식 주의사항을 확인하지 못했어요" in result
    assert health.CONSULT in result
    assert "안전" not in result and "문제없" not in result


def test_family_history_is_not_personal_diagnosis(context, monkeypatch):
    monkeypatch.setattr(health, "_official_cautions", lambda medicine: {
        "product_name": medicine["product_name"], "cautions": "당뇨 환자는 주의한다.",
    })
    assert "직접 연결되는" in ask(selected_medicine=MEDICINE)
    profile = health.load_health_profile("health-user")
    assert "당뇨" not in health._health_terms(profile)


def test_missing_user_never_substitutes_other_profile(context):
    result = gemini.generate_chat_response("질문", user_id="missing", intent="health_precautions")
    assert "건강 정보를 불러오지 못했어요" in result


def test_generation_receives_health_and_official_data(context, monkeypatch):
    monkeypatch.setattr(gemini, "GEMINI_API_KEY", "test-key")
    monkeypatch.setattr("google.genai.Client", MagicMock())
    generation = MagicMock(return_value="확인약정의 공식 자료는 고혈압 환자에게 사용 전 상담하도록 안내해요.")
    monkeypatch.setattr(gemini, "_generate_complete_chat_reply", generation)
    monkeypatch.setattr(health, "_reply_grounded", lambda *args: True)
    result = ask(selected_medicine=MEDICINE)
    prompt = generation.call_args.kwargs["prompt"]
    for value in ("고혈압", "뇌졸중", "페니실린", "당뇨", "폈어요", "가끔 마셔요"):
        assert value in prompt
    assert "가족력은 본인의 질환이 아닙니다" in prompt
    assert "NEVER_SHARE" not in prompt
    assert result.endswith(health.CONSULT)


@pytest.mark.parametrize("reply", [gemini.INCOMPLETE_CHAT_REPLY, "", "근거 없는 답변"])
def test_model_failure_still_delivers_source_content(context, monkeypatch, reply):
    monkeypatch.setattr(gemini, "GEMINI_API_KEY", "test-key")
    monkeypatch.setattr("google.genai.Client", MagicMock())
    monkeypatch.setattr(gemini, "_generate_complete_chat_reply", lambda *args, **kwargs: reply)
    monkeypatch.setattr(health, "_reply_grounded", lambda *args: False)
    result = ask(selected_medicine=MEDICINE)
    assert "고혈압" in result and "확인약정" in result
    assert "답변을 끝까지" not in result and len(result) <= 600


def test_http_contract_accepts_intent_and_health_read_is_nonmutating(context, monkeypatch):
    before = context.read_bytes()
    monkeypatch.setattr("app.services.dur_service.analyze_dur_consultation", MagicMock(side_effect=AssertionError()))
    api = FastAPI()
    api.include_router(router)
    body = {"user_id": "health-user", "message": "내 건강 상태에서 주의할 점은?",
            "intent": "health_precautions", "selected_medicine": MEDICINE}
    assert DrugExplainChatRequest(**body).intent == "health_precautions"
    result = TestClient(api).post("/api/v1/drug-explain/chat", json=body)
    assert result.status_code == 200 and "고혈압" in result.json()["reply"]
    assert set(result.json()["health_highlight_terms"]) == {"고혈압", "음주"}
    assert context.read_bytes() == before


def test_official_identity_mismatch_is_rejected(monkeypatch):
    monkeypatch.setattr("app.services.external_api_service.fetch_e_drug_info", lambda **kw: {
        **SECOND, "cautions": "고혈압 환자는 주의한다.",
    })
    monkeypatch.setattr(gemini, "_with_official_permission_ingredient", lambda medicine, **kw: medicine)
    assert health._official_cautions(MEDICINE) is None


def test_exact_permission_fallback_requires_cautions(monkeypatch):
    monkeypatch.setattr("app.services.external_api_service.fetch_e_drug_info", lambda **kw: None)
    lookup = MagicMock(return_value={**MEDICINE, "_permission_identity_verified": True,
                                   "cautions": "음주 시에는 사용하지 않는다."})
    monkeypatch.setattr(gemini, "_with_official_permission_ingredient", lookup)
    assert health._official_cautions(MEDICINE)["cautions"]
    assert lookup.call_args.kwargs["required_fields"] == {"cautions", "ingredient"}


def test_e_drug_failure_still_tries_permission_database_and_api(monkeypatch):
    monkeypatch.setattr("app.services.external_api_service.fetch_e_drug_info", MagicMock(side_effect=TimeoutError()))
    lookup = MagicMock(return_value={**MEDICINE, "_permission_identity_verified": True,
                                   "cautions": "고혈압 환자는 주의한다."})
    monkeypatch.setattr(gemini, "_with_official_permission_ingredient", lookup)
    assert health._official_cautions(MEDICINE)["product_name"] == "확인약정"
    lookup.assert_called_once()


def test_grounding_checker_fails_closed_on_false_or_truncation(monkeypatch):
    from types import SimpleNamespace
    result = SimpleNamespace(text='{"grounded": true}', candidates=[])
    monkeypatch.setattr(gemini, "_generate_content_with_retry", lambda *args, **kwargs: result)
    assert health._reply_grounded(None, {}, [], "확인한 답변")
    result.text = '{"grounded": false}'
    assert not health._reply_grounded(None, {}, [], "새로운 진단")
    result.text = '{"grounded": true}'
    result.finish_reason = "MAX_TOKENS"
    assert not health._reply_grounded(None, {}, [], "잘린 검증")


def test_health_generation_exception_retains_official_answer(context, monkeypatch):
    monkeypatch.setattr(gemini, "GEMINI_API_KEY", "test-key")
    monkeypatch.setattr("google.genai.Client", MagicMock(side_effect=TimeoutError()))
    result = ask(selected_medicine=MEDICINE)
    assert "고혈압" in result and "확인약정" in result
    assert result.endswith(health.CONSULT)


def test_health_reply_over_length_returns_bounded_evidence_not_failure(context, monkeypatch):
    monkeypatch.setattr(gemini, "GEMINI_API_KEY", "test-key")
    monkeypatch.setattr("google.genai.Client", MagicMock())
    long_reply = "확인약정의 고혈압 관련 주의사항을 확인하세요. " * 50
    monkeypatch.setattr(gemini, "_generate_complete_chat_reply", lambda *args, **kwargs: long_reply)
    monkeypatch.setattr(health, "_reply_grounded", lambda *args: True)
    monkeypatch.setattr(gemini, "_summarize_chat_reply", lambda *args, **kwargs: long_reply)
    result = ask(selected_medicine=MEDICINE)
    assert "고혈압" in result and len(result) <= 600
    assert "요약" not in result


def test_old_unknown_and_negative_lifestyle_are_not_active_conditions():
    profile = {"diseases": [], "past_illnesses": [], "allergies": [],
               "family_illnesses": ["암"], "past_history": True,
               "smoking": "안 폈어요", "drinking": "안 마셔요"}
    assert health._health_terms(profile) == []
    assert not health._mentions("수술 환자", "술")
    assert health._mentions("술을 마시지 않는다.", "술")
    assert not health._mentions("암모니아", "암")


def test_allergy_matches_official_ingredient_and_generic_hypersensitivity_warning(context, monkeypatch):
    monkeypatch.setattr(health, "_official_cautions", lambda medicine: {
        "product_name": medicine["product_name"], "ingredient": "페니실린 100mg",
        "cautions": "이 약의 성분에 과민반응이 있는 환자는 사용하지 않는다.",
    })
    result = ask(selected_medicine=MEDICINE)
    assert "알레르기명과 공식 성분명이 일치" in result
    assert "직접 연결되는" not in result


def test_allergy_never_guesses_cross_reactivity_or_drug_class():
    profile = {"allergies": ["페니실린"]}
    assert health._allergy_matches(profile, {
        "ingredient": "아목시실린", "cautions": "과민반응이 있는 환자는 사용하지 않는다.",
    }) == []


def test_ordinary_question_does_not_read_health_profile(monkeypatch):
    load = MagicMock(side_effect=AssertionError("ordinary path must not change"))
    monkeypatch.setattr(health, "load_health_profile", load)
    assert gemini.generate_chat_response("안녕하세요", user_id="health-user")
    load.assert_not_called()
