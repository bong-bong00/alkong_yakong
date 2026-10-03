// 화면 확인용 가짜 데이터가 실제로 화면에 붙는지 본다.
//
// 이 테스트가 빨개지면 목업만 낡은 것이다 — 모델이 바뀌면 여기부터 고친다.
// dev_mock.dart 를 지울 때 이 파일도 함께 지운다.
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/dev_mock.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_home_screen.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/drug_detail_screen.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/my_medicines_screen.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/prescription_history_screen.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/mypage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => ProviderScope(
  overrides: devMockOverrides(force: true),
  child: MaterialApp(
    theme: AppTheme.build(),
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('오늘 홈이 가짜 하루를 그린다', (tester) async {
    await tester.pumpWidget(_wrap(const PatientHomeScreen()));
    await tester.pump();

    expect(find.text('김복자 님'), findsOneWidget);
    // 아침은 드셨고 점심은 없고 저녁이 남았다.
    expect(find.textContaining('아침'), findsWidgets);
    expect(find.textContaining('없음'), findsWidgets);
    expect(find.text('복용 완료'), findsOneWidget);
  });

  testWidgets('내 약 목록이 가짜 약 세 가지를 그린다', (tester) async {
    await tester.pumpWidget(_wrap(const MyMedicinesScreen(asTab: true)));
    await tester.pumpAndSettle();

    expect(find.text('메트포르민'), findsOneWidget);
    expect(find.text('암로디핀'), findsOneWidget);
    expect(find.text('아스피린'), findsOneWidget);
    // 지난 약은 접혀 있다.
    await tester.scrollUntilVisible(
      find.text('이전에 사용한 약'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('이전에 사용한 약'), findsOneWidget);
  });

  testWidgets('내 정보가 가짜 몸 정보를 그린다', (tester) async {
    await tester.pumpWidget(_wrap(const MyPageScreen()));
    await tester.pumpAndSettle();

    expect(find.text('68세'), findsOneWidget);
    expect(find.text('B형'), findsOneWidget);
    expect(find.text('페니실린'), findsOneWidget);
    expect(find.textContaining('보유 질환 : 고혈압, 당뇨'), findsOneWidget);
    // 쓰는 말은 "내 건강 정보 · 수정"이다. "몸 정보"나 "고치기"가 아니다.
    expect(find.text('내 건강 정보'), findsOneWidget);
    expect(find.text('수정'), findsOneWidget);
  });

  testWidgets('약 자세히가 가짜 설명과 주의를 그린다', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(const DrugDetailScreen(medicineCode: '200701023')),
    );
    await tester.pumpAndSettle();

    expect(find.text('아스피린'), findsOneWidget);

    String shown() => tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
        .join('\n');

    // 탭은 둘. 약 소개 안에 "무슨 약인지"와 "어떻게 먹는지"가 이어진다.
    expect(find.text('약 소개'), findsOneWidget);
    expect(find.text('주의'), findsOneWidget);

    expect(shown(), isNot(contains('주성분 설명')));
    expect(shown(), contains('혈관을 막는 것을 예방'));
    expect(shown(), contains('심근경색'));
    expect(shown(), contains('얼마나'));
    expect(shown(), contains('성분'));
    expect(shown(), isNot(contains('와파린')));

    await tester.tap(find.text('주의'));
    await tester.pumpAndSettle();
    expect(shown(), contains('와파린'));
    expect(shown(), contains('피가 잘 멈추지 않을 수 있어요'));

    // 출처는 박스가 아니라 꼬리말 한 줄이다.
    expect(shown(), contains('정보 출처 · 식약처 의약품 허가정보'));
  });

  testWidgets('처방전 기록이 지금까지 넣은 처방전을 그린다', (tester) async {
    await tester.pumpWidget(_wrap(const PrescriptionHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('행복한내과의원 · 우리약국'), findsOneWidget);
    // 며칠치는 날짜 옆에만 적고, 약 줄에는 이름만 둔다.
    expect(find.text('메트포르민'), findsOneWidget);
    expect(find.textContaining('30일치'), findsOneWidget);
    expect(find.text('한빛정형외과'), findsOneWidget);
  });
}
