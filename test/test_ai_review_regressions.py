from types import SimpleNamespace
from unittest.mock import Mock, MagicMock

import pytest

from app.services import gemini_service as gemini
from app.services.pharmacist import health_precautions as health
from app.services.pharmacist.conversation import conversation_context, record_evidence
from app.services.pharmacist.response_policy import (
    food_only_question, broad_stop_instruction, complete_units, official_excerpt_reply,
)


def response(text):
    return SimpleNamespace(text=text, candidates=[SimpleNamespace(finish_reason='STOP',
        content=SimpleNamespace(parts=[SimpleNamespace(text=text)]))], usage_metadata=None)


def test_verified_short_names_cover_all_products_but_not_same_strength_or_ambiguous_alias():
    names = ('첫약정(성분가)', '둘약정200밀리그램(수출명:Other)')
    assert 'missing_medicine_coverage' not in gemini._chat_response_quality(response('첫약정과 둘약정200밀리그램에 대해 안내해요.'), required_medicine_names=names)[2]
    assert 'missing_medicine_coverage' in gemini._chat_response_quality(response('둘약정100밀리그램에 대해 안내해요.'), required_medicine_names=names[1:])[2]
    assert 'missing_medicine_coverage' in gemini._chat_response_quality(response('첫약정에 대해 안내해요.'), required_medicine_names=('첫약정(성분가)', '첫약정(성분나)'))[2]


@pytest.mark.parametrize('text', ['우유와 같이 먹어도 되나요?', '이 약과 음식은요?', '커피와 같이 먹어도 되나요?'])
def test_food_suggestion_is_not_a_drug_pair_verdict(text):
    assert food_only_question(text)


def test_mixed_food_and_two_drug_question_still_checks_pairs():
    assert not food_only_question('두 약을 같이 먹고 술도 마셔도 되나요?')
    assert not food_only_question('수술 전에 같이 먹는 약은요?')


def test_arbitrary_stop_is_rejected_but_specific_condition_is_not_generalized():
    assert broad_stop_instruction('이러한 증상이 생기면 즉시 약 복용을 중단하세요.')
    assert broad_stop_instruction('평소와 다른 증상이 나타나면 즉시 복용을 중단하세요.')
    assert broad_stop_instruction('졸음이나 입마름이 생길 수 있어요. 이상 증상이 나타나면 즉시 복용을 중단하세요.')
    assert broad_stop_instruction('부작용이 생기면 복용을 중지하세요.')
    assert not broad_stop_instruction('호흡곤란과 전신 발적이 생기면 즉시 진료를 받으세요.')
    assert 'unqualified_stop_instruction' in gemini._chat_response_quality(response('이런 증상이면 즉시 복용을 중단하세요.'))[2]


def test_official_fallback_preserves_whole_conditions_and_scope():
    contexts = [{'product_name': '첫약정', 'cautions': '18세 미만은 사용하지 않는다. 음주를 삼간다.'},
                {'product_name': '둘약정', 'cautions': '중증 신장애 환자는 사용 전 의료진과 상담한다.'}]
    reply = official_excerpt_reply(contexts, {'precautions'})
    assert all(x in reply for x in ('첫약정', '둘약정', '18세 미만', '중증', '일부 내용', '안전하다는 뜻은 아니며'))
    assert complete_units('1.63배 증가한다. 신장애(중증은 1/4로 감량) 환자는 주의한다.') == ['1.63배 증가한다.', '신장애(중증은 1/4로 감량) 환자는 주의한다.']


def test_official_fallback_does_not_quote_only_section_heading():
    reply = official_excerpt_reply([{'product_name': '첫약정',
        'cautions': '사용상의주의사항 1. 신장애 환자는 사용 전 의료진과 상담한다.'}], {'precautions'})
    assert '“사용상의주의사항 1.”' not in reply
    assert '신장애 환자는 사용 전 의료진과 상담한다.' in reply


def test_completed_zero_check_is_not_personal_safety_guarantee():
    reply = gemini._dur_no_match_reply({'combination'}, {
        'status': 'current', 'items': [], 'zero_result_types': ['병용금기']})
    assert '조합은 확인되지 않았어요' in reply
    assert '개인별 복용 안전성을 보장하지는 않아요' in reply


def test_health_coverage_is_per_drug_not_just_alcohol():
    official = [{'product_name': '첫약정(성분)', 'cautions': '신장애 환자는 주의한다. 이 약 복용 시 알코올섭취를 삼가해야 한다.'},
                {'product_name': '둘약정', 'cautions': '천식 환자는 주의한다.'}]
    terms = ['신장', '콩팥', '알코올', '술', '천식']
    assert not health._coverage_complete('첫약정: 음주를 피하세요. 둘약정: 천식에 주의하세요.', official, terms)
    assert health._coverage_complete('첫약정: 콩팥 기능 저하와 음주에 주의하세요. 둘약정: 천식에 주의하세요.', official, terms)
    reply = health._evidence_reply(official, terms, '')
    assert '신장' in reply and '천식' in reply and ('술' in reply or '알코올' in reply)


def test_free_followup_dosage_uses_general_label_and_not_imperative(monkeypatch):
    medicine = {'medicine_code': '123456789', 'product_name': '첫약정', 'source': '허가정보'}
    def generate(*a, **k):
        record_evidence([medicine])
        return '설명서에는 1회 5mg을 복용하도록 되어 있어요. 처방을 확인해 드세요.'
    monkeypatch.setattr(gemini, '_generate_chat_response', generate)
    with conversation_context([]):
        reply = gemini.generate_chat_response('그럼 첫약정은 어떻게 먹어요?')
    assert reply.startswith('다음은 공식 설명서의 일반 용법 안내')
    assert '5mg' in reply and '드세요.' not in reply


def test_short_summary_is_actually_regenerated_and_verified(monkeypatch):
    source = '첫약정에 관한 설명이에요. ' * 25
    monkeypatch.setattr(gemini, '_generate_content_with_retry', Mock(side_effect=[
        response('첫약정은 처방을 확인하고 복용하세요.'), response('{"preserved": true}')]))
    result = gemini._summarize_chat_reply(Mock(), source, medicine_names=('첫약정',), force=True)
    assert len(result) < len(source) * .65


def test_requested_refresh_not_disabled_by_background_switch(monkeypatch):
    import sqlite3
    from app.services import dur_sync_service as sync
    connection = sqlite3.connect(':memory:')
    monkeypatch.setattr(sync, 'DUR_API_KEY', 'synthetic')
    monkeypatch.setattr(sync, 'DUR_AUTO_SYNC', False)
    monkeypatch.setattr(sync, 'get_connection', lambda: connection)
    monkeypatch.setattr(sync, '_sync_ingredient_type', Mock(return_value={'fetched': 0, 'upserted': 0}))
    assert sync.refresh_dur_for_ingredients(['검증성분'])['status'] == 'disabled'
    assert sync.refresh_dur_for_ingredients(['검증성분'], force_refresh=True)['status'] == 'ok'


def test_empty_official_items_are_not_a_fake_one_row_result():
    from app.services.dur_sync_service import _extract_items
    assert _extract_items({}) == []
    assert _extract_items({'item': {}}) == []


def test_food_chip_with_combination_intent_does_not_require_pair_dur(monkeypatch):
    from app.services import chat_context_service as context, external_api_service as external
    from app.services import medication_feature_dur_client as gateway
    medicine = {'medicine_code': '123456789', 'product_name': '첫약정'}
    official = {**medicine, 'source': '허가정보', 'ingredient': '공식성분',
                'cautions': '이 약 복용 시 알코올섭취를 삼가해야 한다.', 'interaction': '음주를 삼간다.'}
    monkeypatch.setattr(gemini, 'GEMINI_API_KEY', 'synthetic')
    monkeypatch.setattr('google.genai.Client', MagicMock())
    monkeypatch.setattr(external, 'fetch_e_drug_info', lambda **kwargs: official)
    monkeypatch.setattr(gemini, '_generate_content_with_retry', lambda *a, **k: SimpleNamespace(parsed={'drug_names': []}))
    monkeypatch.setattr(context, 'load_latest_dur_context', lambda *a, **k: {'status': 'not_required', 'items': []})
    remote = Mock(side_effect=AssertionError('Food question must not call pair DUR'))
    monkeypatch.setattr(gateway, 'load_remote_combination_context', remote)
    generate = Mock(return_value='첫약정의 공식 자료에는 음주를 삼가도록 안내되어 있어요.')
    monkeypatch.setattr(gemini, '_generate_complete_chat_reply', generate)
    with conversation_context([]):
        reply = gemini.generate_chat_response('첫약정과 같이 먹으면 안 되는 음식은요?', selected_medicine=medicine, intent='combination')
    assert '음주' in reply
    assert '음식·음료' in generate.call_args.kwargs['prompt']
    remote.assert_not_called()


def test_dur_zero_result_does_not_replace_similar_efficacy_comparison(monkeypatch):
    from app.services import external_api_service as external, medication_feature_dur_client as gateway
    medicines = [{'medicine_code': '123456789', 'product_name': '첫약정'},
                 {'medicine_code': '987654321', 'product_name': '둘약정'}]
    official = {m['medicine_code']: {**m, 'source': '허가정보', 'ingredient': '성분' + str(i),
                                   'efficacy': '가려움 완화'} for i, m in enumerate(medicines)}
    monkeypatch.setattr(gemini, 'GEMINI_API_KEY', 'synthetic')
    monkeypatch.setattr('google.genai.Client', MagicMock())
    monkeypatch.setattr(external, 'fetch_e_drug_info', lambda **k: official[k['medicine_code']])
    monkeypatch.setattr(gemini, '_generate_content_with_retry', lambda *a, **k: SimpleNamespace(parsed={'drug_names': []}))
    monkeypatch.setattr(gateway, 'load_remote_combination_context', Mock(return_value={
        'status': 'current', 'items': [], 'has_risk': False, 'zero_result_types': ['중복성분', '효능군중복']}))
    generate = Mock(return_value='첫약정과 둘약정은 허가 효능에 가려움 완화라는 공통 사용 목적이 있어요. 임의로 대체하지 마세요.')
    monkeypatch.setattr(gemini, '_generate_complete_chat_reply', generate)
    with conversation_context([]):
        reply = gemini.generate_chat_response('선택한 약 사이에 비슷한 역할이 있나요?', selected_medicines=medicines, intent='duplicate')
    assert '공통 사용 목적' in reply and '검사 기준에 등재된' in reply
    assert '공식 효능' in generate.call_args.kwargs['prompt']
