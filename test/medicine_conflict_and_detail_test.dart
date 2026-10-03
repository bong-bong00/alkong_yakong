import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/core/constants/app_colors.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/core/widgets/senior_card.dart';
import 'package:alkong_yakong/features/medicines/application/user_medicines_controller.dart';
import 'package:alkong_yakong/features/medicines/domain/user_medicine_models.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/my_medicines_screen.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/drug_detail_screen.dart';
import 'package:alkong_yakong/core/widgets/medicine_conflict_card.dart';
import 'package:alkong_yakong/features/dur_analysis/presentation/screens/dur_analysis_screen.dart';
import 'package:alkong_yakong/features/prescription/domain/registration_result.dart';

class _Fixture extends UserMedicinesController {
  @override
  Future<List<UserMedicine>> build() async => [
    UserMedicine.fromJson({
      'medicine_code': 'a',
      'product_name': '코다론정',
      'status': 'active',
      'use_route_type': 'eat',
      'interaction_status': 'risk_found',
      'interaction_conflict_names': ['아디팜정(히드록시진염산염)'],
    }),
    UserMedicine.fromJson({
      'medicine_code': 'b',
      'product_name': '아디팜정',
      'status': 'active',
      'use_route_type': 'eat',
      'interaction_status': 'check_needed',
    }),
    UserMedicine.fromJson({
      'medicine_code': 'c',
      'product_name': '다른약',
      'status': 'active',
      'use_route_type': 'eat',
      'interaction_status': 'check_needed',
    }),
  ];

  @override
  Future<UserMedicine> loadDetail(String code) async => UserMedicine.fromJson({
    'medicine_code': code,
    'product_name': '테스트액',
    'ingredient': '테스트 성분',
    'dose_amount': '1',
    'frequency_per_day': 1,
    'administration_times': ['아침'],
    'official_usage_notice': '제품 설명서의 일반적인 사용법이에요.',
    'interaction_status': 'risk_found',
    'interaction_summary': '확인된 충돌 안내',
    'interaction_conflict_names': ['상대약'],
    'use_route_type': 'apply',
    'ask_doctor_when': ['제거할 의료진 안내'],
    'purpose_notice': '제거할 허가 쓰임 안내',
    'detail_status': 'READY',
    'ingredient_explanation':
        '테스트 성분은 이 약의 주성분으로, 심장 박동을 만드는 전기 신호를 조절해요. 지나치게 빠르거나 불규칙한 심장 박동을 조절하는 데 도움을 줘요.',
    'ingredient_highlight': '지나치게 빠르거나 불규칙한 심장 박동을 조절하는 데 도움을 줘요.',
    'approved_use_summary': '대표 치료 목적',
    'all_approved_uses': ['대표 치료 목적', '추가 공식 허가 목적'],
    'official_usage': '공식 용법 원문',
  });
}

void main() {
  Future<void> mount(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userMedicinesProvider.overrideWith(_Fixture.new)],
        child: MaterialApp(theme: AppTheme.build(), home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('확인된 충돌 상대도 빨간 표시하고 무관한 약은 표시하지 않는다', (tester) async {
    await mount(tester, const MyMedicinesScreen());
    expect(find.text('[충돌]'), findsNWidgets(2));
    for (final name in ['코다론정', '아디팜정', '다른약']) {
      final card = tester.widget<SeniorCard>(
        find.ancestor(of: find.text(name), matching: find.byType(SeniorCard)),
      );
      expect(card.borderColor, name == '다른약' ? isNull : AppColors.danger);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('상세 탭과 언제·쓰는 법 줄은 없고 충돌 안내는 유지한다', (tester) async {
    await mount(tester, const DrugDetailScreen(medicineCode: 'a'));
    for (final label in ['약 소개', '주의', '언제', '쓰는 법']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('내가 처방받은 사용 방법'), findsOneWidget);
    expect(find.text('주성분'), findsOneWidget);
    expect(find.text('이 약의 주성분'), findsOneWidget);
    expect(find.textContaining('전기 신호를 조절해요'), findsNothing);
    expect(find.textContaining('지나치게 빠르거나 불규칙한'), findsOneWidget);
    expect(find.text('이 약 물어보기'), findsOneWidget);
    expect(find.text('어떤 치료에 쓰이나요?'), findsOneWidget);
    expect(find.text('전체 허가 목적'), findsOneWidget);
    expect(find.text('제품 공식 용법·용량'), findsOneWidget);
    expect(find.byType(MedicineConflictCard), findsOneWidget);
    expect(find.textContaining('시간:'), findsNothing);
    expect(find.textContaining('실제 처방 이유는'), findsNothing);
    expect(find.text('언제 의료진에게 알려야 하나요?'), findsNothing);
    expect(find.text('제거할 의료진 안내'), findsNothing);
    expect(find.text('제거할 허가 쓰임 안내'), findsNothing);
    expect(find.textContaining('확인된 충돌 안내'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('미완료에서도 확인된 충돌은 유지하고 개인 금기만 있으면 분리한다', () {
    expect(
      pairConflictMatches({
        'assessment_status': 'INCOMPLETE',
        'matches': [
          {'type': '병용금기'},
          {'type': '연령금기'},
          {'type': '중복성분'},
        ],
      }),
      hasLength(2),
    );
    expect(
      pairConflictMatches({
        'matches': [
          {'type': '연령금기'},
        ],
      }),
      isEmpty,
    );
    expect(pairConflictMatches(null), isEmpty);
  });

  testWidgets('복원한 충돌 화면은 공통 카드와 확인 후 일정 이동을 사용한다', (tester) async {
    var continued = false;
    await mount(
      tester,
      DurAnalysisScreen(
        onOpenScheduleDays: () => continued = true,
        initialResult: {
          'assessment_status': 'INCOMPLETE',
          'analysis_complete': false,
          'matches': [
            {
              'type': '병용금기',
              'medicine_names_a': ['코다론정'],
              'medicine_names_b': ['아디팜정'],
              'why_easy': '확인된 충돌 안내',
            },
          ],
        },
      ),
    );
    expect(find.text('약 함께먹기 주의'), findsOneWidget);
    expect(find.byType(MedicineConflictCard), findsOneWidget);
    expect(find.textContaining('일부 검사는 아직'), findsOneWidget);
    await tester.tap(find.text('확인했어요'));
    expect(continued, isTrue);
    expect(tester.takeException(), isNull);
  });
}
