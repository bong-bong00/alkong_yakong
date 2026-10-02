import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/mode/app_mode.dart';
import '../../../easy_flow/presentation/easy_flow_shell.dart';
import '../../../../core/widgets/senior_bottom_nav.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../biosignal/presentation/screens/measure_screen.dart';
import '../../../biosignal/domain/heart_data.dart';
import '../../../medicines/presentation/screens/my_medicines_screen.dart';
import '../../../profile/presentation/screens/mypage_screen.dart';
import 'medication_record_screen.dart';
import 'patient_home_screen.dart';

/// 환자 쉘 — 탭은 **오늘 · 내 약 · 기록 · 내 정보** 넷이다.
///
/// 시안대로 "내 약"을 상시 탭으로 되돌렸다. 오늘 홈에서 약 이름과
/// 바로가기를 걷어냈으므로, 약을 보고 처방전을 넣고 AI 약사에게 묻는
/// 일은 모두 이 탭 한 자리로 모인다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  /// 방금 기록한 시간대. null이 아니면 오늘 탭이 완료 화면을 그린다.

  static const List<SeniorNavItem> _tabs = [
    SeniorNavItem(icon: TablerIcons.home, label: '오늘'),
    SeniorNavItem(icon: TablerIcons.pill, label: '내 약'),
    SeniorNavItem(icon: TablerIcons.calendar, label: '기록'),
    SeniorNavItem(icon: TablerIcons.user, label: '내 정보'),
  ];

  @override
  Widget build(BuildContext context) {
    // 쉬운 모드는 같은 화면을 한 줄로 이어 붙인 쉘을 쓴다.
    // 화면 자체는 아래 일반 모드와 완전히 같은 것을 부른다.
    if (ref.watch(appModeProvider).isEasy) {
      return const EasyFlowShell();
    }

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: IndexedStack(
        index: _index,
        children: [
          PatientHomeScreen(
            onOpenRecord: () => setState(() => _index = 2),
            // 심박수 관리는 자체 측정 하위 경로를 가진 화면이다. 홈 위에
            // imperative stack으로 섞지 않고 명시 경로로 전환한다.
            onOpenHeartbeat: () => context.go('/biosignal'),
            onOpenPrescription: () => context.push('/prescription'),
            onOpenChat: () => context.push('/drug-explain'),
            // 약 목록은 이제 탭이다. 새 화면을 쌓지 않고 자리만 옮긴다.
            onOpenMedicines: () => setState(() => _index = 1),
            onOpenDrug: (medicine) {
              final code = (medicine.medicineCode ?? medicine.key ?? '').trim();
              if (code.isEmpty) {
                showSeniorSnackbar(
                  context,
                  '이 약의 상세 정보를 찾지 못했어요.',
                  error: true,
                );
                return;
              }
              context.push('/medicines/$code');
            },
            onMeasure: (_) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MeasureScreen(
                  returnToPreviousScreen: true,
                  measurementContext: HeartMeasurementContext.afterMedication,
                ),
              ),
            ),
          ),
          const MyMedicinesScreen(asTab: true),
          // 탭이 오늘로 돌아가는 길이므로 화면 안에 단추를 두지 않는다.
          const MedicationRecordScreen(),
          const MyPageScreen(),
        ],
      ),
      bottomNavigationBar: SeniorBottomNav(
        items: _tabs,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
