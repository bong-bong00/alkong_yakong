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
import 'package:alkong_yakong/features/reminder/presentation/screens/lock_screen_alert.dart';
import 'package:alkong_yakong/features/medicines/domain/drug_info.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/drug_detail_screen.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/my_medicines_screen.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/pharmacist_chat_screen.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/add_medicine_screen.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/manual_medicine_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    '약 설명 (21)': () => const DrugDetailScreen(drug: DrugInfo.metformin),
    'AI 약사 상담 (22)': () => const PharmacistChatScreen(),
    '심박수 관리 (24)': () => const HeartScreen(),
    '폴라 센서 (25)': () => const PolarScreen(data: HeartData.demo),
    '한 달 기록 (26)': () => const MonthlyHeartScreen(data: HeartData.demo),
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
