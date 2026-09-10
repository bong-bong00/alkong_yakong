import 'dart:io';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/auth/presentation/screens/login_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/guardian_home_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/medication_record_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_home_screen.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:alkong_yakong/features/onboarding/presentation/screens/first_run_screen.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/mypage_screen.dart';
import 'package:alkong_yakong/features/reminder/domain/reminder_ladder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/home_screen.dart';
import 'package:alkong_yakong/features/easy_flow/domain/easy_flow.dart';
import 'package:alkong_yakong/core/widgets/senior_bottom_nav.dart';
import 'package:alkong_yakong/core/mode/app_mode.dart';
import 'package:alkong_yakong/features/medication/presentation/screens/dose_done_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 시니어 리디자인의 QA 기준을 코드로 굳힌 테스트.
///
/// 특히 5h — 시스템 글자 크기를 최대로 올렸을 때도 레이아웃이 버텨야 한다.
/// 어떤 화면도 오버플로로 터지면 안 된다.
void main() {
  _forbiddenFeatureTests();
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

  testWidgets('먹었어요는 바로 기록하지 않고 센서 착용부터 묻는다 (13)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const PatientHomeScreen()));
    await tester.pump();

    expect(find.text('먹었어요'), findsOneWidget);
    await tester.tap(find.text('먹었어요'));
    await tester.pumpAndSettle();

    // 기록보다 시트가 먼저다. 띠를 차고 계시면 심박수를 잴 기회이기 때문이다.
    expect(find.textContaining('가슴 띠를'), findsOneWidget);
    expect(find.text('차고 있어요 · 재기'), findsOneWidget);
    expect(find.text('안 차고 있어요 · 복약만 기록'), findsOneWidget);
    expect(find.text('그만두기'), findsOneWidget);
  });

  testWidgets('그만두기를 고르면 아무것도 기록되지 않는다 (13)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var done = 0;
    await tester.pumpWidget(
      wrap(PatientHomeScreen(onDone: () => done++)),
    );
    await tester.pump();

    await tester.tap(find.text('먹었어요'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('그만두기'));
    await tester.pumpAndSettle();

    expect(done, 0);
    expect(find.text('먹었어요'), findsOneWidget);
  });

  testWidgets('복약만 기록을 고르면 완료로 넘어간다 (14)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var done = 0;
    await tester.pumpWidget(
      wrap(PatientHomeScreen(onDone: () => done++)),
    );
    await tester.pump();

    await tester.tap(find.text('먹었어요'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('안 차고 있어요 · 복약만 기록'));
    await tester.pumpAndSettle();

    expect(done, 1);
  });

  testWidgets('완료 화면의 되돌리기는 시간 제한 없이 있다 (14)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(const DoseDoneScreen(slot: DoseSlot.morning)),
    );
    await tester.pump();

    expect(find.textContaining('잘하셨어요'), findsOneWidget);
    expect(find.text('잘못 눌렀어요 · 되돌리기'), findsOneWidget);
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
  testWidgets('쉬운 모드는 탭 대신 "다음 한 걸음" 버튼 하나를 쓴다 (40)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appModeProvider.overrideWith((ref) => _EasyMode())],
        child: MaterialApp(theme: AppTheme.build(), home: const HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(SeniorBottomNav), findsNothing);
    expect(find.text(kEasyFlow.first.nextLabel), findsOneWidget);
    // 아바타 자리가 메뉴 버튼으로 바뀐다.
    expect(find.text('메뉴'), findsOneWidget);
    // 모드 배지는 파랑으로 차 있다.
    expect(find.text('쉬운 화면'), findsOneWidget);
  });

  testWidgets('약을 안 눌렀는데 넘어가려 하면 한 번 묻는다 (42)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appModeProvider.overrideWith((ref) => _EasyMode())],
        child: MaterialApp(theme: AppTheme.build(), home: const HomeScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(kEasyFlow.first.nextLabel));
    await tester.pumpAndSettle();

    // 자동으로 "안 드셨어요"로 확정하지 않는다.
    expect(find.textContaining('아직 안 누르셨어요'), findsOneWidget);
    expect(find.text('먹었어요 · 다음으로'), findsOneWidget);
    expect(find.text('그냥 넘어갈게요'), findsOneWidget);
    expect(find.text('이 화면에 그대로 있기'), findsOneWidget);
  });

  test('쉬운 모드가 부르는 화면은 모두 일반 모드에도 있는 화면이다', () {
    for (final step in kEasyFlow) {
      expect(EasyScreen.values.contains(step.screen), isTrue);
    }
    final screens = kEasyFlow.map((s) => s.screen).toList();
    expect(screens.toSet().length, screens.length);
  });

  test('모든 단계에 다음 버튼 라벨이 있다', () {
    for (final step in kEasyFlow) {
      expect(step.nextLabel.trim(), isNotEmpty);
    }
  });

  test('측정 중에는 하단 바를 숨긴다', () {
    // 자기 흐름을 끝까지 마쳐야 하는 화면에서는 "다음"이 방해가 된다.
    expect(showsEasyBar(EasyScreen.measure), isFalse);
    expect(showsEasyBar(EasyScreen.today), isTrue);
  });

  test('메뉴에서 갈 수 있는 곳이 흐름보다 넓다', () {
    // 한 줄로만 갈 수 있으면 그것대로 갇힌다.
    expect(kEasyMenu.length, greaterThan(kEasyFlow.length));
  });
}

/// 테스트에서 쉬운 모드로 고정하기 위한 알림자.
class _EasyMode extends AppModeNotifier {
  _EasyMode() {
    state = AppMode.easy;
  }
}

// ════════════════════════════════════════════════════════════════
//  핸드오프가 금지한 것들 — 되살아나면 여기서 걸린다
// ════════════════════════════════════════════════════════════════

void _forbiddenFeatureTests() {
  final libDir = Directory('lib');

  List<File> dartFiles() => libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('음성으로 복약을 기록하는 화면이 없다', () {
    final voiceDir = Directory('lib/features/voice');
    expect(voiceDir.existsSync(), isFalse, reason: '음성 기능은 제거 대상이다');

    for (final file in dartFiles()) {
      final text = file.readAsStringSync();
      expect(text.contains('VoiceScreen'), isFalse, reason: file.path);
      expect(text.contains("'/voice'"), isFalse, reason: file.path);
    }
  });

  test('어르신 화면에 전화 거는 버튼이 없다', () {
    // 보호자 화면의 "전화 드리기"는 방향이 반대라 허용된다.
    const guardianOnly = 'guardian_home_screen.dart';
    for (final file in dartFiles()) {
      if (file.path.endsWith(guardianOnly)) continue;
      final text = file.readAsStringSync();
      for (final banned in ["label: '약국에 전화하기'", "전화를 겁니다"]) {
        expect(text.contains(banned), isFalse,
            reason: '${file.path}에 "$banned"가 남아 있다');
      }
    }
  });

  test('보호자 연락은 스낵바로 알린다', () {
    final dur = File(
      'lib/features/dur_analysis/presentation/screens/dur_analysis_screen.dart',
    ).readAsStringSync();
    expect(dur.contains('showSeniorSnackbar'), isTrue);
  });
}
