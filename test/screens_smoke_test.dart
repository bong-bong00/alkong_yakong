import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/core/widgets/recovery_view.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/measure_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/monthly_heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/polar_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/saved_screen.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_data.dart';
import 'package:alkong_yakong/features/auth/presentation/screens/signup_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/month_calendar_screen.dart';
import 'package:alkong_yakong/features/dur_analysis/presentation/screens/dur_analysis_screen.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/care_family_screen.dart';
import 'package:alkong_yakong/features/reminder/presentation/screens/alarm_settings_screen.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/prescription_screen.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/account_screen.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/help_screen.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/notices_screen.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/policy_screen.dart';
import 'package:alkong_yakong/features/reminder/presentation/screens/lock_screen_alert.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/drug_detail_screen.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/my_medicines_screen.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/pharmacist_chat_screen.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/add_medicine_screen.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/manual_medicine_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/features/biosignal/data/heart_repository.dart';

/// 서버 대신 정해 둔 기록을 돌려준다. null이면 "못 읽음"이다.
class _FakeHeartRepository extends HeartRepository {
  _FakeHeartRepository(this.result);
  final HeartData? result;

  @override
  Future<HeartData?> fetch({String? userId}) async => result;
}

/// 테스트에서만 쓰는 채워진 기록. 앱 코드에는 이런 값을 두지 않는다.
const _heartSample = HeartData(
  today: HeartPair(before: 78, after: 72),
  todaySlotLabel: '저녁 약',
  beforeAt: '오후 5시 52분',
  afterAt: '오후 6시 40분',
  week: [
    HeartDay('월', HeartPair(before: 80, after: 74)),
    HeartDay('화', HeartPair(before: 78, after: 71)),
    HeartDay('수', HeartPair()),
    HeartDay('목', HeartPair(before: 77, after: 70)),
    HeartDay('금', HeartPair(before: 84, after: 86)),
    HeartDay('토', HeartPair()),
    HeartDay('일', HeartPair(before: 78, after: 72)),
  ],
  month: [
    HeartMonthDay(1, HeartPair(before: 79, after: 73)),
    HeartMonthDay(2, HeartPair()),
    HeartMonthDay(3, HeartPair(before: 96, after: 84)),
    HeartMonthDay(4, HeartPair(before: 78, after: 72)),
    HeartMonthDay(5, HeartPair(before: 76, after: 70)),
    HeartMonthDay(6, HeartPair(before: 80, after: 74)),
    HeartMonthDay(7, HeartPair()),
    HeartMonthDay(8, HeartPair(before: 77, after: 72)),
    HeartMonthDay(9, HeartPair(before: 79, after: 73)),
    HeartMonthDay(10, HeartPair(before: 78, after: 71)),
    HeartMonthDay(11, HeartPair(before: 82, after: 76)),
    HeartMonthDay(12, HeartPair(before: 80, after: 74)),
    HeartMonthDay(13, HeartPair(before: 77, after: 70)),
    HeartMonthDay(14, HeartPair(before: 78, after: 72)),
  ],
  streakDays: 9,
  bestStreakDays: 9,
  anomaly: HeartAnomaly(day: 3, slotLabel: '저녁', before: 96, after: 84),
  sensorConnected: false,
  sensorBattery: null,
  sensorLastReadAt: '',
  notifyGuardian: true,
);

/// 읽기는 됐지만 잰 값이 하나도 없는 기록 — 서버가 빈 칸만 채워 보낸 모양.
const _heartEmpty = HeartData(
  today: HeartPair(),
  todaySlotLabel: '저녁 약',
  beforeAt: '',
  afterAt: '',
  week: [
    HeartDay('월', HeartPair()),
    HeartDay('화', HeartPair()),
    HeartDay('수', HeartPair()),
    HeartDay('목', HeartPair()),
    HeartDay('금', HeartPair()),
    HeartDay('토', HeartPair()),
    HeartDay('일', HeartPair()),
  ],
  month: [HeartMonthDay(1, HeartPair()), HeartMonthDay(2, HeartPair())],
  streakDays: 0,
  bestStreakDays: 0,
  anomaly: null,
  sensorConnected: false,
  sensorBattery: null,
  sensorLastReadAt: '',
  notifyGuardian: true,
);

/// 나머지 화면들이 두 배율 모두에서 터지지 않고 그려지는지 본다.
void main() {
  Widget wrap(Widget child, {double textScale = 1.0}) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.build(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: child,
        ),
      ),
    );
  }

  final dose = DoseEntry(
    slot: DoseSlot.dinner,
    medicines: const [
      Medicine(ingredient: '메트포르민 500mg', amount: '1알'),
      Medicine(ingredient: '암로디핀 5mg', amount: '1알'),
    ],
  );

  final screens = <String, Widget Function()>{
    '처방전 찍기 (4d)': () => const PrescriptionScreen(),
    '약 함께먹기 주의 (4f)': () => const DurAnalysisScreen(),
    '약 넣기 방법 고르기 (07)': () => AddMedicineScreen(onPick: (_) {}),
    '손으로 적기 (10)': () => const ManualMedicineScreen(),
    '내 약 목록 (20)': () => const MyMedicinesScreen(),
    '약 설명 (21)': () => const DrugDetailScreen(medicineCode: '200701021'),
    'AI 약사 상담 (22)': () => const PharmacistChatScreen(),
    // 심박 화면은 서버에서 읽은 기록만 그린다. 채운·빈·실패 세 모양을 다 본다.
    '심박수 관리 (24)': () =>
        HeartScreen(repository: _FakeHeartRepository(_heartSample)),
    '심박수 관리 · 기록 없음 (24)': () =>
        HeartScreen(repository: _FakeHeartRepository(_heartEmpty)),
    '심박수 관리 · 못 불러옴 (24)': () =>
        HeartScreen(repository: _FakeHeartRepository(null)),
    '폴라 센서 (25)': () => const PolarScreen(),
    '한 달 기록 (26)': () =>
        MonthlyHeartScreen(data: _heartSample, now: DateTime(2026, 9, 14)),
    '한 달 기록 · 기록 없음 (26)': () =>
        MonthlyHeartScreen(data: _heartEmpty, now: DateTime(2026, 9, 14)),
    '심박수 재는 중 (27)': () => const MeasureScreen(),
    '기록 저장 (30)': () => const SavedScreen(bpm: 72),
    '회원가입 (02~05)': () => const SignupScreen(),
    '가입 완료': () => const SignupDoneScreen(name: '김복자'),
    '이번 달 달력 (19)': () => const MonthCalendarScreen(),
    '복약 알림 (32)': () => const AlarmSettingsScreen(),
    '돌보는 분 목록 (36)': () => Scaffold(
      body: CareFamilyScreen(onOpenPatient: (_) {}),
    ),
    '계정 관리': () => const AccountScreen(),
    '도움이 필요할 때': () => const HelpScreen(),
    '도움이 필요할 때 (모두 펼침)': () => const HelpScreen(openAll: true),
    '알려드릴 소식': () => const NoticesScreen(),
    '이용약관': () => const PolicyScreen.terms(),
    '개인정보처리방침': () => const PolicyScreen.privacy(),
    '잠금화면 알림 (5b)': () => LockScreenAlert(
      dose: dose,
      now: DateTime(2026, 8, 20, 18),
      onTake: () {},
      onSnooze: () {},
    ),
    '연결 끊김 회복 (5e)': () => Scaffold(
      body: RecoveryView(
        title: '지금은 심장 박동을\n재지 못하고 있어요',
        reassurance: '가슴에 찬 띠와 전화기가 떨어져 있어요. ',
        reassuranceEmphasis: '고장이 아니니 걱정하지 마세요.',
        steps: const ['띠가 가슴에 잘 붙어 있는지 만져보세요', '띠의 가운데 단추를 한 번 누르세요'],
        actionLabel: '다시 연결하기',
        onAction: () {},
        stillWorksTitle: '약 알림은 그대로 와요',
        stillWorksBody: '띠가 끊겨도 복약 알림에는 영향이 없어요.',
        helperText: '그래도 안 되면\n딸 지안 님에게 도움 청하기',
        onCallHelper: () {},
        footnote: '마지막으로 잰 시각 · 오늘 오전 11시 20분',
      ),
    ),
  };

  for (final scale in <double>[1.0, 2.0]) {
    group('글자 배율 ${scale}x', () {
      screens.forEach((name, build) {
        testWidgets(name, (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(wrap(build(), textScale: scale));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
        });
      });
    });
  }
}
