import 'package:alkong_yakong/features/medicines/domain/user_medicine_models.dart';
import 'package:alkong_yakong/features/medicines/domain/official_purpose_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/core/constants/app_colors.dart';
import 'package:alkong_yakong/core/widgets/senior_card.dart';
import 'package:alkong_yakong/features/medicines/application/user_medicines_controller.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/my_medicines_screen.dart';

class _GroupedFixture extends UserMedicinesController {
  @override
  Future<List<UserMedicine>> build() async => [
    for (final entry in {
      'eat': '테스트정',
      'apply': '테스트액',
      'unknown': '미확인약',
    }.entries)
      UserMedicine.fromJson({
        'medicine_code': entry.key,
        'product_name': entry.value,
        'status': 'active',
        'use_route_type': entry.key,
        'interaction_status': switch (entry.key) {
          'eat' => 'risk_found',
          'apply' => 'none',
          _ => 'check_needed',
        },
      }),
  ];
}

void main() {
  testWidgets('내 약 목록은 먹는 약·바르는 약·미확인 약을 별도 카드로 구분한다', (tester) async {
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userMedicinesProvider.overrideWith(_GroupedFixture.new)],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: const MyMedicinesScreen(asTab: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      '먹는 약',
      '바르는 약',
      '사용 방법 확인 필요',
      '테스트정',
      '테스트액',
      '미확인약',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('붙이는 약'), findsNothing);
    expect(find.text('[충돌]'), findsOneWidget);
    for (final name in ['테스트정', '테스트액', '미확인약']) {
      final card = tester.widget<SeniorCard>(
        find.ancestor(of: find.text(name), matching: find.byType(SeniorCard)),
      );
      expect(card.borderColor, name == '테스트정' ? AppColors.danger : isNull);
      if (name == '테스트정') expect(card.borderWidth, 3);
    }
    expect(tester.takeException(), isNull);
  });
  test('서버의 사용 구분을 그대로 사용하고 unknown을 먹는 약으로 바꾸지 않는다', () {
    for (final type in MedicineUseType.values) {
      final medicine = UserMedicine.fromJson({
        'medicine_code': '123',
        'product_name': '테스트정',
        'dosage_form': '정제',
        'administration_route': 'eat',
        'use_route_type': type.name,
      });
      expect(medicine.useType, type);
      expect(medicine.doseAction, type.action);
    }
    final unclassified = UserMedicine.fromJson({
      'product_name': '미확인액',
      'administration_route': 'eat',
    });
    expect(unclassified.useType, MedicineUseType.unknown);
  });

  test('허가 목적은 모든 원문·괄호·제한 문구를 유지하며 줄만 나눈다', () {
    const raw =
        '다음의 피부질환 : 습진·피부염군(아토피피부염, 지루피부염, 접촉성알레르기피부염, 유사건선, 편평태선, 가려움발진 포함)';
    final layout = OfficialPurposeLayout.fromText(raw);
    expect(layout.heading, '다음의 피부질환 :');
    expect(layout.body, contains('\n'));
    String withoutSpace(String value) => value.replaceAll(RegExp(r'\s+'), '');
    expect(withoutSpace(layout.heading + layout.body), withoutSpace(raw));
    for (final text in [
      '1,000 mg',
      '08:00',
      '특정 질환(확인 필요',
      '성인에게 1~2 mg을 사용한다.',
    ]) {
      final formatted = OfficialPurposeLayout.fromText(text);
      expect(formatted.heading, '');
      expect(formatted.body, text);
    }
  });
}
