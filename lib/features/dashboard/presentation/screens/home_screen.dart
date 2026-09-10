import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/mode/app_mode.dart';
import '../../../easy_flow/presentation/easy_flow_shell.dart';
import '../../../../core/widgets/senior_bottom_nav.dart';
import '../../../biosignal/presentation/screens/measure_screen.dart';
import '../../../medication/domain/medication_models.dart';
import '../../../medication/presentation/screens/dose_done_screen.dart';
import '../../../medicines/domain/drug_info.dart';
import '../../../medicines/presentation/screens/drug_detail_screen.dart';
import '../../../medicines/presentation/screens/my_medicines_screen.dart';
import '../../../reminder/presentation/screens/alarm_settings_screen.dart';
import '../../../medicines/presentation/screens/pharmacist_chat_screen.dart';
import '../../../prescription/presentation/screens/prescription_screen.dart';
import '../../../profile/presentation/screens/mypage_screen.dart';
import 'medication_record_screen.dart';
import 'patient_home_screen.dart';

/// 환자 쉘 — 탭은 **오늘 · 기록 · 내 정보** 셋뿐이다.
///
/// 기존 4탭(홈·약 정보·기록·내 정보)에서 "약 정보"를 뺐다.
/// 한 화면 = 핵심 행동 하나라는 원칙에 따라, 약 설명은 필요한 자리
/// (처방전 확인, 함께먹기 주의)에서 열리게 하고 상시 탭에서는 내렸다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  /// 방금 기록한 시간대. null이 아니면 오늘 탭이 완료 화면을 그린다.
  DoseSlot? _justRecorded;

  static const List<SeniorNavItem> _tabs = [
    SeniorNavItem(icon: TablerIcons.pill, label: '오늘'),
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
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _index,
        children: [
          _justRecorded == null
              ? PatientHomeScreen(
                  onOpenRecord: () => setState(() => _index = 1),
                  onOpenHeartbeat: () => context.push('/biosignal'),
                  onOpenPrescription: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrescriptionScreen(),
                    ),
                  ),
                  onOpenChat: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PharmacistChatScreen(),
                    ),
                  ),
                  onOpenMedicines: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MyMedicinesScreen(
                        onOpenAlarm: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AlarmSettingsScreen(),
                          ),
                        ),
                        onAddPrescription: () => Navigator.of(context)
                            .pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const PrescriptionScreen(),
                              ),
                            ),
                      ),
                    ),
                  ),
                  onOpenDrug: (medicine) {
                    final drug = DrugInfo.find(medicine.key);
                    if (drug == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DrugDetailScreen(
                          drug: drug,
                          onOpenInteraction: () =>
                              context.push('/dur-analysis'),
                        ),
                      ),
                    );
                  },
                  onDone: () =>
                      setState(() => _justRecorded = DoseSlot.dinner),
                  onMeasure: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MeasureScreen(),
                      ),
                    );
                    if (mounted) {
                      setState(() => _justRecorded = DoseSlot.dinner);
                    }
                  },
                )
              : DoseDoneScreen(
                  slot: _justRecorded!,
                  onUndone: () => setState(() => _justRecorded = null),
                ),
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
