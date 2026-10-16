from unittest.mock import Mock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from app.routes.drug_explain import router
from app.services import gemini_service as gemini


def test_general_mode_is_forwarded_and_does_not_read_health_highlights():
    app = FastAPI()
    app.include_router(router)
    with patch.object(gemini, 'generate_chat_response', return_value='일반 안내') as generate, \
         patch('app.services.pharmacist.health_precautions.health_highlight_terms') as health:
        response = TestClient(app).post('/api/v1/drug-explain/chat', json={
            'user_id':'guardian', 'message':'건강 주의', 'intent':'health_precautions',
            'consultation_mode':'general'})
    assert response.status_code == 200
    assert generate.call_args.kwargs['general_consultation'] is True
    assert generate.call_args.kwargs['user_id'] == 'guardian'
    health.assert_not_called()


def test_general_health_does_not_load_any_profile(monkeypatch):
    health = Mock(side_effect=AssertionError('No personal health lookup'))
    monkeypatch.setattr('app.services.pharmacist.health_precautions.generate_health_reply', health)
    reply = gemini.generate_chat_response('건강정보로 약 주의사항 알려줘', user_id='guardian',
        intent='health_precautions', general_consultation=True)
    assert '개인 건강정보를 사용하지 않아요' in reply
    health.assert_not_called()


def test_general_all_medicines_never_loads_registered_medicines(monkeypatch):
    load = Mock(side_effect=AssertionError('No current medicine lookup'))
    monkeypatch.setattr('app.services.medication_feature_dur_client.load_remote_current_medicines', load)
    reply = gemini.generate_chat_response('제가 현재 먹는 약 전체를 알려주세요.', user_id='guardian',
        intent='overview', general_consultation=True)
    assert '검색해서 선택' in reply
    load.assert_not_called()


def test_general_single_duplicate_does_not_compare_against_own_medicines():
    reply = gemini.generate_chat_response('이 약과 비슷한 효과가 있나요?', user_id='guardian',
        selected_medicine={'medicine_code':'123456789','product_name':'검증정'},
        intent='duplicate', general_consultation=True)
    assert '두 개 이상' in reply


def test_general_single_combination_explicitly_excludes_current_medicines(monkeypatch):
    from types import SimpleNamespace
    from unittest.mock import MagicMock
    from app.services.pharmacist.conversation import conversation_context
    from app.services import external_api_service as external, medication_feature_dur_client as gateway
    medicine = {'medicine_code':'123456789','product_name':'검증정'}
    official = {**medicine,'source':'허가정보','ingredient':'검증성분','interaction':'병용 주의 문구'}
    monkeypatch.setattr(gemini,'GEMINI_API_KEY','synthetic')
    monkeypatch.setattr('google.genai.Client',MagicMock())
    monkeypatch.setattr(external,'fetch_e_drug_info',lambda **kwargs:official)
    monkeypatch.setattr(gemini,'_generate_content_with_retry',lambda *a,**k:SimpleNamespace(parsed={'drug_names':[]}))
    remote = Mock(return_value={'status':'incomplete','items':[]})
    monkeypatch.setattr(gateway,'load_remote_combination_context',remote)
    with conversation_context([]):
        gemini.generate_chat_response('검증정과 같이 먹어도 돼요?',user_id='guardian',
            selected_medicine=medicine,intent='combination',general_consultation=True)
    assert remote.call_args.kwargs['include_current_medicines'] is False
    assert remote.call_args.kwargs['user_id'] == 'guardian'
