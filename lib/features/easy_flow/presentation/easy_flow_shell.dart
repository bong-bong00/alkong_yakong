import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/mode/app_mode.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/senior_button.dart';
import '../../biosignal/presentation/screens/heart_screen.dart';
import '../../biosignal/presentation/screens/measure_screen.dart';
import '../../dashboard/presentation/screens/medication_record_screen.dart';
import '../../dashboard/presentation/screens/patient_home_screen.dart';
import '../../dur_analysis/presentation/screens/dur_analysis_screen.dart';
import '../../medication/application/medication_controller.dart';
import '../../medication/domain/medication_models.dart';
import '../../medication/presentation/screens/dose_done_screen.dart';
import '../../medicines/presentation/screens/my_medicines_screen.dart';
import '../../medicines/presentation/screens/pharmacist_chat_screen.dart';
import '../../prescription/presentation/screens/prescription_screen.dart';
import '../../profile/presentation/screens/mypage_screen.dart';
import '../domain/easy_flow.dart';
import 'widgets/easy_sheets.dart';

/// 쉬운 모드 쉘.
///
/// 구성은 일반 모드와 **동일**하다. 달라지는 것은 셋뿐이다.
/// 1. 헤더의 모드 배지가 파랑으로 차고, 아바타 자리가 "메뉴"가 된다.
/// 2. 하단에 "다음 한 걸음" 버튼 하나가 붙는다.
/// 3. 화면 안의 주 버튼 일부를 숨긴다 — 하단 바가 그 역할을 대신하기 때문.
class EasyFlowShell extends ConsumerStatefulWidget {
  const EasyFlowShell({super.key});

  @override
  ConsumerState<EasyFlowShell> createState() => _EasyFlowShellState();
}

class _EasyFlowShellState extends ConsumerState<EasyFlowShell> {
  EasyScreen _screen = EasyScreen.today;

  /// 지나온 화면. "이전"에서 하나씩 꺼낸다.
  final List<EasyScreen> _history = <EasyScreen>[];

  /// 흐름 안에서 지금 화면이 몇 번째인지. 흐름 밖이면 -1.
  int get _flowIndex =>
      kEasyFlow.indexWhere((step) => step.screen == _screen);

  String get _nextLabel {
    final index = _flowIndex;
    if (index < 0) return kEasyFallbackLabel;
    return kEasyFlow[index].nextLabel;
  }

  void _goTo(EasyScreen screen) {
    if (screen == _screen) return;
    setState(() {
      _history.add(_screen);
      if (_history.length > 40) _history.removeAt(0);
      _screen = screen;
    });
  }

  void _back() {
    if (_history.isEmpty) return;
    setState(() => _screen = _history.removeLast());
  }

  /// 다음 한 걸음.
  Future<void> _next() async {
    final index = _flowIndex;

    // 흐름 밖이면 오늘 화면으로 되돌린다.
    if (index < 0) {
      _goTo(EasyScreen.today);
      return;
    }

    // 오늘 화면에서 저녁 약을 아직 안 눌렀는데 넘어가려 하면 한 번 묻는다.
    if (_screen == EasyScreen.today) {
      final dose = ref.read(medicationProvider).doseOf(DoseSlot.dinner);
      if (!dose.taken) {
        final choice = await showSkipConfirmSheet(
          context,
          slotLabel: dose.slot.label,
        );
        if (!mounted) return;
        switch (choice) {
          case SkipChoice.stay:
            return;
          case SkipChoice.takeAndContinue:
            ref.read(medicationProvider.notifier).takeAnyway(DoseSlot.dinner);
          case SkipChoice.skip:
            break;
        }
      }
    }

    final nextIndex = index + 1;
    _goTo(
      nextIndex < kEasyFlow.length
          ? kEasyFlow[nextIndex].screen
          : EasyScreen.today,
    );
  }

  Future<void> _openMenu() async {
    final result = await showEasyMenuSheet(context, userName: '복자');
    if (!mounted || result == null) return;
    if (result.leaveEasyMode) {
      await ref.read(appModeProvider.notifier).set(AppMode.normal);
      return;
    }
    if (result.screen != null) _goTo(result.screen!);
  }

  /// 일반 모드가 쓰는 화면을 그대로 부른다.
  Widget _buildScreen() {
    switch (_screen) {
      case EasyScreen.today:
        return PatientHomeScreen(
          easyMode: true,
          onOpenMenu: _openMenu,
          onOpenRecord: () => _goTo(EasyScreen.record),
          onOpenHeartbeat: () => _goTo(EasyScreen.heart),
          onOpenMedicines: () => _goTo(EasyScreen.medicines),
          onOpenChat: () => _goTo(EasyScreen.chat),
          onOpenPrescription: () => _goTo(EasyScreen.prescription),
          onDone: () => _goTo(EasyScreen.done),
          onMeasure: () => _goTo(EasyScreen.measure),
        );
      case EasyScreen.done:
        return DoseDoneScreen(
          slot: DoseSlot.dinner,
          onUndone: () => _goTo(EasyScreen.today),
        );
      case EasyScreen.record:
        return const MedicationRecordScreen();
      case EasyScreen.heart:
        return const HeartScreen();
      case EasyScreen.medicines:
        return const MyMedicinesScreen();
      case EasyScreen.prescription:
        // 등록이 끝나면 손대지 않아도 함께먹기 주의로 넘어간다.
        return PrescriptionScreen(
          onCompleted: () => _goTo(EasyScreen.interaction),
        );
      case EasyScreen.interaction:
        return const DurAnalysisScreen();
      case EasyScreen.chat:
        return const PharmacistChatScreen();
      case EasyScreen.measure:
        return const MeasureScreen();
      case EasyScreen.myInfo:
        return const MyPageScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showBar = showsEasyBar(_screen);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: KeyedSubtree(
        // 화면마다 새로 만든다. 보이지도 않는 화면이 센서를 잡고 있지 않도록.
        key: ValueKey(_screen),
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: _buildScreen(),
        ),
      ),
      bottomNavigationBar: showBar
          ? _EasyFlowBar(
              label: _nextLabel,
              onNext: _next,
              onBack: _history.isEmpty ? null : _back,
            )
          : null,
    );
  }
}

/// 다음 한 걸음 바.
class _EasyFlowBar extends StatelessWidget {
  final String label;
  final VoidCallback onNext;
  final VoidCallback? onBack;

  const _EasyFlowBar({
    required this.label,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Color(0xFFDDDDE6), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x2914161E),
            blurRadius: 34,
            offset: Offset(0, -12),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onBack != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SeniorTextButton(
                    label: '이전으로',
                    expand: false,
                    fontSize: 17,
                    onPressed: onBack,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              SeniorButton(
                label: label,
                minHeight: 76,
                fontSize: 24,
                radius: 20,
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 헤더 오른쪽의 "메뉴" 버튼. 쉬운 모드에서 아바타 자리를 대신한다.
class EasyMenuButton extends StatelessWidget {
  final VoidCallback onTap;

  const EasyMenuButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '메뉴 열기',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 17),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Text('메뉴', style: AppText.cardTitle(size: 19)),
        ),
      ),
    );
  }
}
