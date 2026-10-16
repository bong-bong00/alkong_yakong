"""Regressions reproduced from the deployed guardian response audit."""
from types import SimpleNamespace
from unittest.mock import MagicMock, Mock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
import pytest

from app.routes.drug_explain import router
from app.services import gemini_service as gemini
from app.services import external_api_service as official, medication_feature_dur_client as gateway
from app.services.pharmacist.conversation import conversation_context
from app.services.pharmacist.response_policy import official_excerpt_reply, label_units

MEDS = [dict(medicine_code='197800210', product_name='아디팜정'),
        dict(medicine_code='197800308', product_name='프리마란정')]


@pytest.fixture
def providers(monkeypatch):
    monkeypatch.setattr(gemini, 'GEMINI_API_KEY', 'synthetic')
    monkeypatch.setattr('google.genai.Client', MagicMock())
    monkeypatch.setattr(official, 'fetch_e_drug_info', lambda **kw: dict(
        next(m for m in MEDS if m['medicine_code'] == kw['medicine_code']),
        ingredient='검증성분', source='허가정보', efficacy='검증 효능 안내', usage='검증 용법 안내',
        cautions='졸음이 나타날 수 있으므로 운전에 주의하세요.'))
    monkeypatch.setattr(gateway, 'load_remote_current_medicines', lambda **kw: dict(status='current', items=MEDS))
    remote = Mock(return_value=dict(status='current', items=[], has_risk=False,
        zero_result_types=['병용금기', '중복성분', '효능군중복']))
    monkeypatch.setattr(gateway, 'load_remote_combination_context', remote)
    monkeypatch.setattr(gemini, '_generate_complete_chat_reply', lambda *a, **kw: '두 약의 효능은 일부 비슷하지만 같은 약은 아니에요.')
    monkeypatch.setattr(gemini, '_generate_content_with_retry', lambda *a, **kw: SimpleNamespace(parsed={'drug_names': []}))
    return remote


@pytest.mark.parametrize('intent,message', [
    ('precautions', '약을 보관할 때 일반적으로 확인할 주의사항을 알려주세요.'),
    ('overview', '약 설명서에서 확인해야 하는 항목을 쉽게 알려주세요.'),
    ('overview', '약을 먹을 때 물로 먹어야 하나요?'),
])
def test_general_buttons_equal_typed_answers_without_provider(intent, message):
    with patch.object(gemini, 'GEMINI_API_KEY', ''), patch.object(official, 'fetch_e_drug_info') as fetch:
        with conversation_context([]) as evidence:
            button = gemini.generate_chat_response(message, intent=intent, general_consultation=True)
        typed = gemini.generate_chat_response(message, general_consultation=True)
    assert button == typed
    assert '확인할 수 없어' not in button
    assert evidence['sources'] and not evidence['medicines']
    fetch.assert_not_called()


@pytest.mark.parametrize('intent', ['combination', 'duplicate'])
def test_patient_all_keeps_every_medicine_in_dur_request(providers, intent):
    api = FastAPI()
    api.include_router(router)
    message = ('환자에게 등록된 약 전체를 같이 먹을 때 주의할 점을 확인해 주세요.' if intent == 'combination'
               else '환자에게 등록된 약 전체에서 같은 성분이나 비슷한 역할이 겹치는지 확인해 주세요.')
    response = TestClient(api).post('/api/v1/drug-explain/chat', json=dict(
        user_id='synthetic-patient', consultation_mode='patient_all', intent=intent, message=message))
    assert response.status_code == 200
    args = providers.call_args.kwargs
    assert args['include_current_medicines'] is False
    assert args['additional_medicines'] == MEDS
    assert '식약처 DUR 정보' in response.json()['sources']


def test_headings_never_count_as_a_meaningful_warning():
    reply = official_excerpt_reply([dict(product_name='검증정', cautions=(
        '1. 다음 환자에는 투여하지 말 것. 1) 이 약에 과민반응이 있는 환자에게 사용하지 마세요. '
        '2. 일반적 주의.'))], {'precautions'})
    assert '과민반응' in reply
    assert '“다음 환자에는 투여하지 말 것.”' not in reply
    empty = official_excerpt_reply([dict(product_name='검증정', cautions='다음 환자에는 투여하지 말 것.')], {'precautions'})
    assert '세부 조건' in empty and '공식 안내 일부' not in empty
    qualified = official_excerpt_reply([dict(product_name='검증정', cautions='다음 환자는 과민반응이 있는 경우 사용하지 말 것.')], {'precautions'})
    assert '과민반응' in qualified


def test_numbered_headings_are_not_quoted_as_a_warning():
    for heading in ('이상반응 5.', '이상반응 4.', '3. 이상반응 5.', '상호작용 6.',
                    '임산부 및 수유부에 대한 투여', '적용상의 주의(주사제에 한함)', '과민반응 환자'):
        reply = official_excerpt_reply([dict(product_name='검증정', cautions=heading)], {'precautions'})
        assert '공식 안내 일부' not in reply
    units = label_units('1. 다음 환자에는 투여하지 말 것. 1) 과민반응 환자 2) 임부 2. 이상반응 5.')
    assert units == ['다음 환자에는 투여하지 말 것: 과민반응 환자', '다음 환자에는 투여하지 말 것: 임부']
    assert label_units('다음 환자에는 투여하지 말 것(경구: 정제). 1) 과민반응 환자') == [
        '다음 환자에는 투여하지 말 것(경구: 정제): 과민반응 환자']
    assert label_units('다음 환자에는 투여하지 말 것: 1) 과민반응 환자') == [
        '다음 환자에는 투여하지 말 것: 과민반응 환자']


def test_oral_product_does_not_quote_injection_only_instructions():
    reply = official_excerpt_reply([dict(product_name='검증정', cautions=(
        '적용상의 주의(주사제에 한함): 천천히 주사한다. 졸음이 나타날 수 있으므로 운전에 주의하세요.'))], {'precautions'})
    assert '주사한다' not in reply and '운전' in reply
    injection = official_excerpt_reply([dict(product_name='정우검증주사', cautions='적용상의 주의(주사제에 한함): 천천히 주사한다.')], {'precautions'})
    assert '천천히 주사한다' in injection
    separate = official_excerpt_reply([dict(product_name='검증정', cautions=(
        '12. 적용상의 주의(주사제에 한함). 1) 천천히 주사한다. '
        '13. 일반적 주의. 1) 졸음이 나타날 수 있으므로 운전에 주의하세요.'))], {'precautions'})
    assert '주사한다' not in separate and '운전' in separate


def test_label_extraction_preserves_nested_conditions_and_fractions():
    text = '1. 다음 환자에는 신중히 투여할 것. 1) 신장애 환자(중등증의 경우 용량의 1/2, 중증은 1/4; 2) 조건을 함께 확인)'
    units = label_units(text)
    assert len(units) == 1 and '신중히 투여할 것' in units[0]
    assert '1/2' in units[0] and '1/4' in units[0] and '2) 조건' in units[0]


def test_general_single_combination_requests_the_second_medicine(providers):
    reply = gemini.generate_chat_response('아디팜정을 함께 먹을 때 주의할 점이 있는지 확인해 주세요.',
        selected_medicine=MEDS[0], intent='combination', general_consultation=True)
    assert '다른 약' in reply and '확인하지 못' not in reply
    providers.assert_not_called()


@pytest.mark.parametrize('reply', ['선생님처럼 고령자이신 경우 주의해야 해요.', '사용자는 임신 중이므로 확인해 주세요.'])
def test_unprovided_personal_attributes_are_rejected(reply):
    response = SimpleNamespace(text=reply, candidates=[SimpleNamespace(finish_reason='STOP')])
    assert 'unsupported_personal_attribute' in gemini._chat_response_quality(response)[2]


def test_patient_audience_is_neutral_not_the_guardian_taking_medicines():
    with conversation_context([], consultation_mode='patient_all'), patch.object(
        gemini, '_generate_chat_response', return_value='선생님께서 드시는 약의 설명이에요. 선생님의 처방을 확인하세요.'):
        reply = gemini.generate_chat_response('등록된 약의 사용 목적은요?')
    assert '환자에게 등록된 약' in reply and '선생님의' not in reply


def test_followup_summary_never_grows_if_compression_fails():
    previous = '검증정은 주의해서 사용하세요. 일부 조건은 확인하지 못했어요.'
    history = [dict(role='assistant', content=previous)]
    with conversation_context(history, summary_requested=True), patch.object(gemini, '_generate_chat_response', return_value='새 답변. ' * 90), \
         patch('google.genai.Client'), patch.object(gemini, '_summarize_chat_reply', return_value='더 긴 답변. ' * 90) as summarize:
        reply = gemini.generate_chat_response('이 질문의 답변을 더 짧게 요약해 주세요.')
    assert '요약하지 못' in reply
    assert summarize.call_args.kwargs['max_chars'] < len(previous)


def test_followup_returns_successfully_shortened_verified_reply():
    previous = '검증정은 주의하세요. ' * 30
    with conversation_context([dict(role='assistant', content=previous)], summary_requested=True), \
         patch.object(gemini, '_generate_chat_response', return_value='검증정은 주의하세요. ' * 50), \
         patch('google.genai.Client'), patch.object(gemini, '_summarize_chat_reply', return_value='검증정은 주의하세요.'):
        reply = gemini.generate_chat_response('짧게 요약해 주세요.')
    assert reply == '검증정은 주의하세요.' and len(reply) < len(previous)


def test_prior_answer_policy_is_invalidated():
    from app.services.pharmacist.cache_context import REPLY_POLICY_VERSION
    assert REPLY_POLICY_VERSION >= 5
