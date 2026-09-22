"""Display-only tests: no application lifespan, real DB or external services."""
import unittest
from contextlib import ExitStack
from unittest.mock import Mock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.models.response_schemas import DrugExplanationContentResponse
from app.services import drug_explain_service as detail
from app.services import medicine_detail_service as mds
from app.services import user_medicines_service as user_detail
from app.routes import drug_explain, users


class DetailPhase1Test(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch('sqlite3.connect', side_effect=AssertionError('real DB forbidden')))
        self.stack.enter_context(patch('socket.create_connection', side_effect=AssertionError('network forbidden')))
        self.stack.enter_context(patch.object(detail, '_fetch_mfds_info', side_effect=AssertionError('external lookup')))
        self.stack.enter_context(patch.object(detail, 'generate_card_from_source', side_effect=AssertionError('generation')))
        self.medicine = {'medicine_code': 'synthetic', 'product_name': '합성 제품',
                         'ingredient': '합성성분', 'manufacturer': '합성', 'usage': '1회 0.5 mL를 바른다.'}
        self.profile = {'status': 'READY', 'review_status': 'REVIEWED',
                        'source_hash': mds.official_source_hash(self.medicine),
                        'ingredient_explanation': '합성성분은 정해진 작용을 돕는 성분이에요.',
                        'approved_uses': ['증상 가: 성인에 한하여 증상 가에 사용한다. 소아에는 사용하지 않는다.'],
                        'source_verified': True}
        self.stack.enter_context(patch.object(detail, 'get_medicine_detail_profile', side_effect=lambda *args: self.profile))
        self.card = self.stack.enter_context(patch.object(detail, '_get_latest_reviewed_card', return_value=None))
        self.cursor = Mock()
        def execute(sql, params):
            self.assertTrue(sql.lstrip().upper().startswith('SELECT'))
            self.assertIn('normalized_key=?', sql)
            row = {'ingredient_name': '합성성분', 'explanation': self.profile['ingredient_explanation'],
                   'use_help': '정해진 작용을 돕는', 'role_explanation': ''}
            return Mock(fetchone=lambda: row if params == ('합성성분',) else None)
        self.cursor.execute.side_effect = execute

    def payload(self):
        return detail.reviewed_detail_payload(self.cursor, self.medicine)

    def test_defaults(self):
        result = DrugExplanationContentResponse(content_available=False, review_status='UNAVAILABLE').model_dump()
        self.assertEqual(result['ingredient_highlight'], '')
        self.assertEqual(result['treatment_uses'], [])

    def test_highlight_exact_key_and_substring(self):
        result = self.payload()['explanation']
        self.assertEqual(result['ingredient_highlight'], '정해진 작용을 돕는')
        self.assertIn(result['ingredient_highlight'], result['ingredient_explanation'])
        self.medicine['ingredient'] = '다른성분'
        self.assertEqual(self.payload()['explanation']['ingredient_highlight'], '')

    def test_empty_profile_explanation_uses_reviewed_fallback(self):
        self.profile['ingredient_explanation'] = ''
        reviewed = {
            '합성성분': {
                'explanation': '합성성분은 정해진 작용을 돕는 성분이에요.',
                'use_help': '정해진 작용을 돕는',
                'role_explanation': '',
            }
        }
        with patch.object(detail, 'find_reviewed_ingredient_explanations', return_value=reviewed):
            result = self.payload()['explanation']
        self.assertEqual(
            result['ingredient_explanation'],
            '합성성분은 정해진 작용을 돕는 성분이에요.',
        )
        self.assertEqual(result['ingredient_highlight'], '정해진 작용을 돕는')

    def test_nonmatching_highlight_is_empty(self):
        self.profile['ingredient_explanation'] = '다른 설명이에요.'
        self.assertEqual(self.payload()['explanation']['ingredient_highlight'], '')

    def test_treatment_keyword_groups_from_official_text(self):
        heartburn = mds.treatment_use_items(
            '',
            [],
            ['1. 위·십이지장궤양, 위산과다, 속쓰림 및 역류성 식도염'],
        )
        self.assertEqual(heartburn[0]['title'], '속쓰림·위 불편감')
        self.assertEqual(
            heartburn[0]['description'],
            '위산과 관련된 속쓰림이나 위 불편감을 줄이는 데 사용해요.',
        )
        allergy = mds.treatment_use_items(
            '',
            [],
            ['알레르기로 인한 가려움, 불안 및 긴장 증상의 완화'],
        )
        self.assertEqual(
            [item['title'] for item in allergy],
            ['알레르기로 인한 가려움', '불안·긴장'],
        )
        self.assertEqual(mds.treatment_use_items('', [], []), [])

    def test_outdated_cannot_fallback_to_reviewed_card(self):
        self.profile['status'] = 'OUTDATED'
        self.profile['all_approved_uses'] = ['과거 목적']
        self.medicine.update(short_explanation='과거 설명', explanation_review_status='REVIEWED')
        self.card.return_value = {'summary': '과거 카드', 'ingredient_explanation': '과거 설명'}
        result = self.payload()
        self.card.assert_not_called()
        for key in ('ingredient_explanation', 'ingredient_highlight', 'approved_use_summary'):
            self.assertEqual(result['explanation'][key], '')
        for key in ('approved_uses', 'all_approved_uses', 'treatment_uses'):
            self.assertEqual(result['explanation'][key], [])
        self.assertFalse(result['explanation']['content_available'])
        self.assertEqual(result['official_usage']['text'], self.medicine['usage'])

    def test_summary_restriction_is_not_lost_when_full_uses_exist(self):
        self.profile.update(
            approved_use_summary='성인에게만 사용한다.',
            approved_uses=['치통'],
            all_approved_uses=['치통'],
        )
        result = self.payload()['explanation']
        self.assertEqual(result['approved_use_summary'], '성인에게만 사용한다.')
        self.assertEqual(result['approved_uses'], ['치통'])
        self.assertEqual(result['all_approved_uses'], ['치통'])
        self.assertEqual(result['treatment_uses'][0]['title'], '여러 통증')

    def test_existing_fields_and_safety_preserved(self):
        self.profile.update(key_cautions=['주의 원문'], possible_side_effects=['부작용 원문'])
        result = self.payload()
        self.assertEqual(result['safety']['key_cautions'], ['주의 원문'])
        self.assertEqual(result['safety']['possible_side_effects'], ['부작용 원문'])
        self.assertEqual(result['explanation']['approved_uses'], self.profile['approved_uses'])
        self.assertEqual(result['explanation']['treatment_uses'][0], {
            'title': self.profile['approved_uses'][0],
            'description': '',
        })
        self.assertEqual(result['medicine']['medicine_code'], 'synthetic')

    def test_both_real_routes_serialize_common_payload_without_writes(self):
        conn = Mock()
        conn.cursor.return_value = self.cursor
        conn.execute.return_value.fetchone.return_value = self.medicine
        self.stack.enter_context(patch.object(detail, 'get_connection', return_value=conn))
        self.stack.enter_context(patch.object(detail, '_get_medicine', return_value=self.medicine))
        self.stack.enter_context(patch.object(user_detail, 'get_connection', return_value=conn))
        self.stack.enter_context(patch.object(user_detail, '_usage_select', return_value=''))
        self.stack.enter_context(patch.object(user_detail, '_latest_interaction_result', return_value=None))
        self.stack.enter_context(patch.object(user_detail, '_enrich_medicine_row', return_value={**self.medicine, 'amount': '0.5 mL'}))
        self.stack.enter_context(patch.object(user_detail, 'person_cautions_for_medicine', return_value=[]))
        self.stack.enter_context(patch.object(user_detail, 'ensure_user_codarone_available'))
        app = FastAPI()  # No production startup/DB initialization.
        app.include_router(drug_explain.router)
        app.include_router(users.router)
        with TestClient(app) as client:
            for path in ('/api/v1/drug-explain/synthetic', '/api/v1/users/synthetic-user/medicines/synthetic'):
                response = client.get(path)
                self.assertEqual(response.status_code, 200, response.text)
                result = response.json()['explanation']
                self.assertEqual(result['ingredient_highlight'], '정해진 작용을 돕는')
                self.assertEqual(len(result['treatment_uses']), 1)
        for call in conn.execute.call_args_list:
            self.assertTrue(call.args[0].lstrip().upper().startswith('SELECT'))
        conn.commit.assert_not_called()

    def test_full_or_blank_highlight_is_not_emitted_and_body_is_preserved(self):
        body = '  합성성분은 정해진 작용을 돕는 성분이에요.  '
        self.profile['ingredient_explanation'] = body
        for candidate in (body, body.strip(), ' ' + body + ' ', '', '없는 구절'):
            with self.subTest(candidate=candidate), patch.object(detail, 'find_reviewed_ingredient_explanations',
                    return_value={'합성성분': {'use_help': candidate}}):
                result = self.payload()['explanation']
                self.assertEqual(result['ingredient_highlight'], '')
                # Existing payload trimming is unchanged; no clipping/rewording.
                self.assertEqual(result['ingredient_explanation'], body.strip())

    def test_unmatched_official_items_keep_title_only(self):
        items = mds.treatment_use_items('', [], ['성인: 1회 사용한다.'])
        self.assertEqual(items, [{'title': '성인: 1회 사용한다.', 'description': ''}])

    def test_single_ingredient_compose_uses_role_and_use_help(self):
        entries = mds.ingredient_entries('시메티딘')
        text = mds._compose_reviewed_ingredient_explanation(
            entries,
            {
                entries[0]['key']: {
                    'role_explanation': '위산과 관련된',
                    'use_help': '속쓰림이나 위 불편감을 줄이는 데 사용해요.',
                    'explanation': '시메티딘은 이 약의 주성분이에요.',
                }
            },
        )
        self.assertIn('주성분으로', text)
        self.assertTrue(text.startswith('시메티딘은 '))

    def test_response_layer_keeps_numeric_age_and_exception_distinctions(self):
        originals = ['증상 가: 성인에게 1~2 mg을 사용한다.', '증상 가: 성인에게 12 mg을 사용한다.',
                     '증상 가: 12세 이상만 사용한다. 단, 해당 조건은 제외한다.']
        self.profile.update(approved_uses=[], all_approved_uses=originals)
        result = self.payload()['explanation']
        self.assertEqual(result['all_approved_uses'], originals)
        self.assertEqual(
            [item['title'] for item in result['treatment_uses']],
            originals,
        )


if __name__ == '__main__':
    unittest.main()
