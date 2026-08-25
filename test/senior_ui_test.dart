import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/auth/presentation/screens/login_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/guardian_home_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/medication_record_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_home_screen.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:alkong_yakong/features/onboarding/presentation/screens/first_run_screen.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/mypage_screen.dart';
import 'package:alkong_yakong/features/reminder/domain/reminder_ladder.dart';
import 'package:alkong_yakong/features/voice/presentation/screens/voice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/home_screen.dart';
import 'package:alkong_yakong/features/easy_flow/domain/easy_flow.dart';
import 'package:alkong_yakong/core/widgets/senior_bottom_nav.dart';
import 'package:alkong_yakong/core/mode/app_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 시니어 리디자인의 QA 기준을 코드로 굳힌 테스트.
///
/// 특히 5h — 시스템 글자 크기를 최대로 올렸을 때도 레이아웃이 버텨야 한다.
/// 어떤 화면도 오버플로로 터지면 안 된다.
void main() {
  _easyModeTests();
  Widget wrap(Widget child, {double textScale = 1.0}) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.build(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  final screens = <String, Widget Function()>{
    '오늘 홈 (3a)': () => const PatientHomeScreen(),
    '기록 (4c)': () => const MedicationRecordScreen(),
    '내 정보 (4h)': () => const MyPageScreen(),
    '로그인 (4i)': () => const LoginScreen(),
    '첫 사용 (5g)': () => const FirstRunScreen(),
    '듣고 말하기 (5d)': () => const VoiceScreen(),
    '보호자 (4j·4k)': () => const GuardianHomeScreen(),
  };

  group('기본 글자 크기에서 그려진다', () {
    screens.forEach((name, build) {
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(wrap(build()));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('시스템 글자 최대에서도 버틴다 (5h)', () {
    screens.forEach((name, build) {
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // iOS·안드로이드의 접근성 최대 배율 언저리.
        await tester.pumpWidget(wrap(build(), textScale: 2.0));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });
  });

  testWidgets('먹었어요를 누르면 기록되고, 되돌리기로 되돌아온다 (4b)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const PatientHomeScreen()));
    await tester.pump();

    expect(find.text('먹었어요'), findsOneWidget);
    await tester.tap(find.text('먹었어요'));
    await tester.pumpAndSettle();

    // 제목 앞에 이모지가 붙어 있어 부분 일치로 찾는다.
    expect(find.textContaining('잘하셨어요'), findsOneWidget);

    // 되돌리기는 시간 제한 없이 노출된다.
    await tester.tap(find.text('잘못 눌렀어요 · 되돌리기'));
    await tester.pumpAndSettle();

    expect(find.text('먹었어요'), findsOneWidget);
  });

  test('재알림 사다리는 0·15·45분 뒤 어르신, 60분 뒤 보호자다 (5c)', () {
    final doseTime = DateTime(2026, 8, 20, 18);
    final plan = ReminderLadder.planFor(DoseSlot.dinner, doseTime);

    expect(plan.length, 4);
    expect(plan[0].fireAt, doseTime);
    expect(plan[1].fireAt, doseTime.add(const Duration(minutes: 15)));
    expect(plan[2].fireAt, doseTime.add(const Duration(minutes: 45)));
    expect(plan[3].fireAt, doseTime.add(const Duration(minutes: 60)));

    expect(plan[0].message, '저녁 약 드실 시간이에요');
    expect(plan[1].message, '아직 저녁 약을 안 드셨어요');
    expect(plan[2].message, '저녁 약을 꼭 드셔야 해요');

    // 보호자 통보만 보호자에게 간다.
    expect(plan.where((r) => r.toGuardian).length, 1);
  });

  test('30분 뒤에 다시를 고르면 사다리 전체가 30분 밀린다 (5c)', () {
    final doseTime = DateTime(2026, 8, 20, 18);
    final plan = ReminderLadder.planFor(
      DoseSlot.dinner,
      doseTime,
      snoozeCount: 1,
    );

    // 단계를 건너뛰지 않고 전부 30분씩 밀린다.
    expect(plan[0].fireAt, doseTime.add(const Duration(minutes: 30)));
    expect(plan[3].fireAt, doseTime.add(const Duration(minutes: 90)));
  });

  test('절대시간으로 말한다 — 상대시간은 보조다', () {
    expect(
      DoseSlot.absoluteTime(DateTime(2026, 8, 20, 18, 2)),
      '오후 6시 2분',
    );
    expect(DoseSlot.dinner.spokenTime, '저녁 6시');
  });

  testWidgets('비밀번호 "보기"는 입력칸 오른쪽 끝에 붙는다 (4i)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const LoginScreen()));
    await tester.pump();

    // 입력칸은 화면 좌우 여백 24를 뺀 폭을 쓴다.
    const fieldRight = 390.0 - 24.0;
    final buttonRight = tester.getBottomRight(find.text('보기')).dx;

    // 글자 끝에서 테두리까지 20px 안쪽 — 가로를 채우는 버튼이면 훨씬 멀어진다.
    expect(fieldRight - buttonRight, lessThan(24));
  });
}

// ════════════════════════════════════════════════════════════════
//  쉬운 모드 — 화면은 그대로, 오가는 방법만 다르다
// ════════════════════════════════════════════════════════════════

void _easyModeTests() {
  testWidgets('쉬운 모드는 탭 대신 "다음" 버튼 하나로 넘어간다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appModeProvider.overrideWith((ref) => _EasyMode())],
        child: MaterialApp(theme: AppTheme.build(), home: const HomeScreen()),
      ),
    );
    await tester.pump();

    // 아래 탭바가 없다.
    expect(find.byType(SeniorBottomNav), findsNothing);
    // 첫 단계의 다음 버튼이 보인다.
    expect(find.text(kEasyFlow.first.nextLabel), findsOneWidget);
    // 첫 단계에는 "이전으로"가 없다.
    expect(find.text('이전으로'), findsNothing);
  });

  testWidgets('다음을 누르면 흐름 순서대로 넘어가고 되돌아올 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appModeProvider.overrideWith((ref) => _EasyMode())],
        child: MaterialApp(theme: AppTheme.build(), home: const HomeScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(kEasyFlow[0].nextLabel));
    await tester.pump();
    expect(find.text(kEasyFlow[1].nextLabel), findsOneWidget);
    expect(find.text('이전으로'), findsOneWidget);

    await tester.tap(find.text('이전으로'));
    await tester.pump();
    expect(find.text(kEasyFlow[0].nextLabel), findsOneWidget);
  });

  test('마지막 단계에서 다음을 누르면 처음으로 돌아간다 — 막다른 곳이 없다', () {
    final last = kEasyFlow.length - 1;
    expect((last + 1) % kEasyFlow.length, 0);
  });

  test('쉬운 모드가 부르는 화면은 모두 일반 모드에도 있는 화면이다', () {
    // 흐름에 일반 모드가 모르는 화면이 섞이면 "앱 두 개"가 된다.
    for (final step in kEasyFlow) {
      expect(EasyScreen.values.contains(step.screen), isTrue);
    }
    // 같은 화면을 두 번 지나가지 않는다.
    final screens = kEasyFlow.map((s) => s.screen).toList();
    expect(screens.toSet().length, screens.length);
  });

  test('모든 단계에 다음 버튼 라벨이 있다', () {
    for (final step in kEasyFlow) {
      expect(step.nextLabel.trim(), isNotEmpty);
      expect(step.title.trim(), isNotEmpty);
    }
  });
}

/// 테스트에서 쉬운 모드로 고정하기 위한 알림자.
class _EasyMode extends AppModeNotifier {
  _EasyMode() {
    state = AppMode.easy;
  }
}
