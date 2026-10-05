import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/core/constants/app_colors.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/medicines/application/user_medicines_controller.dart';
import 'package:alkong_yakong/features/medicines/domain/user_medicine_models.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/drug_detail_screen.dart';

/// 서버가 어느 약에나 넣어 주는 안내 한 줄과 설명서 용법만 있는 약.
const _generalAdvice = '약을 쓰는 동안 불편한 증상이 생기거나 사용 방법이 걱정될 때 의사나 약사에게 알려주세요.';
const _labelUsage = '메퀴타진으로서 1회 5 mg 1일 2회 경구투여한다.';

class _Fixture extends UserMedicinesController {
  @override
  Future<List<UserMedicine>> build() async => const [];

  @override
  Future<UserMedicine> loadDetail(String code) async => UserMedicine.fromJson({
    'medicine_code': code,
    'product_name': '프리마란정',
    'status': 'active',
    'use_route_type': 'eat',
    'interaction_status': 'none',
    'ask_doctor_when': [_generalAdvice],
    'official_usage': _labelUsage,
    if (code == 'prescribed') ...{
      'dose_amount': '0.5',
      'frequency_per_day': 3,
    },
  });
}

void main() {
  Future<void> mount(WidgetTester tester, String code) async {
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userMedicinesProvider.overrideWith(_Fixture.new)],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: DrugDetailScreen(medicineCode: code),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final cautionDot = find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).color == AppColors.danger &&
        (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
  );

  testWidgets('어느 약에나 붙는 안내만 있으면 주의 탭에 붉은 점을 달지 않는다', (tester) async {
    await mount(tester, 'prescribed');
    expect(cautionDot, findsNothing);
    // 안내 자체는 주의 탭에 그대로 보인다.
    await tester.tap(find.text('주의'));
    await tester.pumpAndSettle();
    expect(find.textContaining('의사나 약사에게 알려주세요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('처방이 있어도 설명서 용법은 "설명서 기준"을 밝혀 보여 준다', (tester) async {
    await mount(tester, 'prescribed');
    expect(find.text('얼마나'), findsOneWidget);
    expect(find.text('복용법'), findsOneWidget);
    expect(find.textContaining('설명서 기준으로, '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('처방을 모르면 설명서 용법을 보여 준다', (tester) async {
    await mount(tester, 'label-only');
    expect(find.text('얼마나'), findsNothing);
    expect(find.text('복용법'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
