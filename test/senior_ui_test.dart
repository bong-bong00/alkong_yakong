import 'dart:io';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/auth/presentation/screens/login_screen.dart';
import 'package:alkong_yakong/features/auth/domain/exclusive_choice.dart';
import 'package:alkong_yakong/features/auth/presentation/screens/signup_screen.dart';
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
  _signupTests();
  _calendarTests();
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


/// 회원가입 — 한 화면에 하나만 묻고, 배타 선택을 지킨다.
void _signupTests() {
  Widget wrap(Widget child) => ProviderScope(
        child: MaterialApp(theme: AppTheme.build(), home: child),
      );

  /// 걸음 수는 역할과 성별에 따라 달라진다(임신 단계는 여성에게만 뜬다).
  /// 그러니 총 개수를 박지 않고 "지금 몇 번째인지 늘 보인다"만 지킨다.
  final stepLabel = RegExp(r'^\d+ / \d+$');

  testWidgets('걸음마다 지금 어디쯤인지 알려준다 (02~05)', (tester) async {
    await tester.pumpWidget(wrap(const SignupScreen()));
    expect(find.textContaining(stepLabel), findsOneWidget);
    expect(find.text('1 / 10'), findsOneWidget);
    expect(find.text('어떤 분이신가요?'), findsOneWidget);
  });

  testWidgets('역할을 고르지 않으면 버튼 위에 이유가 뜬다 (02)', (tester) async {
    await tester.pumpWidget(wrap(const SignupScreen()));
    await tester.tap(find.text('다음'));
    await tester.pump();
    expect(find.text('어떤 분인지 골라주세요'), findsOneWidget);
    // 오류가 떠도 화면은 그대로다 — 다음으로 넘어가지 않는다.
    expect(find.text('어떤 분이신가요?'), findsOneWidget);
  });

  test('"잘 모르겠어요"를 누르면 고른 약 이름이 비워진다 (05)', () {
    final picked = toggleChoice({'페니실린', '아스피린'}, '잘 모르겠어요');
    expect(picked, {'잘 모르겠어요'});
  });

  test('"잘 모르겠어요" 뒤에 약을 고르면 그쪽이 빠진다 (05)', () {
    final picked = toggleChoice({'잘 모르겠어요'}, '페니실린');
    expect(picked, {'페니실린'});
  });

  test('"없어요"도 같은 규칙을 따른다 (05)', () {
    expect(toggleChoice({'고혈압', '당뇨'}, '없어요'), {'없어요'});
    expect(toggleChoice({'없어요'}, '고혈압'), {'고혈압'});
  });

  test('한 번 더 누르면 풀린다', () {
    expect(toggleChoice({'고혈압', '당뇨'}, '당뇨'), {'고혈압'});
  });

  testWidgets('기본 정보를 채우면 다음 걸음으로 넘어간다 (03)', (tester) async {
    await tester.pumpWidget(wrap(const SignupScreen()));

    await tester.tap(find.text('약을 드시는 분'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '김복자');
    await tester.enterText(find.byType(TextField).at(1), '01012345678');
    await tester.enterText(find.byType(TextField).at(2), 'abc123');
    await tester.enterText(find.byType(TextField).at(3), 'abc123');
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    expect(find.text('생년월일과 성별을\n알려주세요'), findsOneWidget);
  });

  testWidgets('보호자는 건강 질문을 받지 않는다', (tester) async {
    await tester.pumpWidget(wrap(const SignupScreen()));
    // 보호자는 남의 복약을 지켜볼 뿐이라 자기 지병을 물을 이유가 없다.
    await tester.tap(find.text('돌보는 가족'));
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('되살린 건강 질문들이 글자 2배에서도 버틴다 (5h)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: const SignupScreen(),
          ),
        ),
      ),
    );

    // 0단계 · 역할
    await tester.tap(find.text('약을 드시는 분'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    // 1단계 · 기본 정보
    await tester.enterText(find.byType(TextField).at(0), '김복자');
    await tester.enterText(find.byType(TextField).at(1), '01012345678');
    await tester.enterText(find.byType(TextField).at(2), 'abc123');
    await tester.enterText(find.byType(TextField).at(3), 'abc123');
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    // 2단계 · 생년월일과 성별
    await tester.tap(find.text('생년월일'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('여성'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    // 3단계 · 키·몸무게·혈액형. 여기서 터지면 혈액형 여덟 칸이 범인이다.
    expect(find.text('혈액형'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    // 4단계 · 임신 (여성일 때만 나온다)
    expect(find.text('임신 준비중'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('약을 고를 때 참고할 것들을 빠짐없이 묻는다', () {
    final source = File(
      'lib/features/auth/presentation/screens/signup_screen.dart',
    ).readAsStringSync();
    // 임신·수유는 병용금기 판정을 통째로 바꾼다. 빠지면 안 된다.
    for (final question in [
      "title: '키, 몸무게, 혈액형을",
      "title: '임신 계획이",
      "title: '담배와 술을",
      "title: '약물 알레르기가",
      "title: '지금 앓고 있는",
      "title: '과거에 앓았거나",
      "title: '보호자 연락처를",
    ]) {
      expect(source.contains(question), isTrue, reason: '$question 단계가 없다');
    }
  });
}

/// 달력은 색과 표시만 쓴다. 칸 안에서 숫자를 세게 하지 않는다.
void _calendarTests() {
  test('달력 칸에는 복용 횟수를 적지 않는다 (19)', () {
    final source = File(
      'lib/features/dashboard/presentation/screens/month_calendar_screen.dart',
    ).readAsStringSync();
    // 칸이 가질 수 있는 상태는 네 가지뿐이다.
    expect(source.contains('enum DayMark { done, missed, today, future }'),
        isTrue);
    // 빠뜨린 날은 색으로 끝내지 않고 글로 다시 적는다.
    expect(source.contains('_MissedCard'), isTrue);
  });

  test('로그아웃 시트는 안전한 쪽이 주 버튼이다 (35)', () {
    final source = File(
      'lib/features/profile/presentation/widgets/logout_sheet.dart',
    ).readAsStringSync();
    final safe = source.indexOf("label: '그대로 쓸게요'");
    final logout = source.indexOf("label: '로그아웃'");
    expect(safe, greaterThan(-1));
    expect(logout, greaterThan(safe), reason: '로그아웃이 주 버튼보다 앞에 오면 안 된다');
    expect(source.contains('SeniorButtonKind.dangerQuiet'), isTrue);
  });
}
