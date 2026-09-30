import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/mode/app_mode.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/senior_button.dart';
import '../../../core/widgets/senior_card.dart';
import '../../biosignal/presentation/screens/heart_screen.dart';
import '../../biosignal/presentation/screens/measure_screen.dart';
import '../../dashboard/presentation/screens/medication_record_screen.dart';
import '../../dur_analysis/presentation/screens/dur_analysis_screen.dart';
import 'easy_dose_screen.dart';
import '../../medication/application/medication_controller.dart';
import '../../medication/domain/medication_models.dart';
import '../../medication/presentation/screens/dose_done_screen.dart';
import '../../medicines/presentation/screens/my_medicines_screen.dart';
import '../../medicines/presentation/screens/pharmacist_chat_screen.dart';
import '../../prescription/presentation/screens/prescription_screen.dart';
import '../../prescription/presentation/screens/schedule_days_screen.dart';
import '../../profile/application/current_user_controller.dart';
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
  Map<String, dynamic>? _durResult;

  /// 방금 기록한 시간대. 완료 화면이 저녁이라고 우기지 않게 들고 있는다.
  DoseSlot? _recordedSlot;

  /// 지나온 화면. "이전"에서 하나씩 꺼낸다.
  final List<EasyScreen> _history = <EasyScreen>[];

  /// 흐름 안에서 지금 화면이 몇 번째인지. 흐름 밖이면 -1.
  int get _flowIndex => kEasyFlow.indexWhere((step) => step.screen == _screen);

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

    // 오늘 화면에서 아직 안 드신 약이 있는데 넘어가려 하면 한 번 묻는다.
    if (_screen == EasyScreen.today) {
      final pending = ref.read(medicationProvider).nextDose;
      if (pending != null) {
        final choice = await showSkipConfirmSheet(
          context,
          slotLabel: pending.slot.label,
        );
        if (!mounted) return;
        switch (choice) {
          case SkipChoice.stay:
            return;
          case SkipChoice.takeAndContinue:
            ref.read(medicationProvider.notifier).takeAnyway(pending.slot);
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
    final result = await showEasyMenuSheet(
      context,
      userName: ref.read(currentUserNameProvider),
    );
    if (!mounted || result == null) return;
    if (result.leaveEasyMode) {
      await ref.read(appModeProvider.notifier).set(AppMode.normal);
      return;
    }
    if (result.screen == EasyScreen.chat) {
      context.push('/drug-explain');
      return;
    }
    if (result.screen != null) _goTo(result.screen!);
  }

  /// 일반 모드가 쓰는 화면을 그대로 부른다.
  Widget _buildScreen() {
    switch (_screen) {
      case EasyScreen.today:
        // 시안의 쉬운 화면은 일반 화면과 다른 장이다. 고를 것을 없애고
        // 이번에 드실 약만 늘어놓는다.
        return const EasyDoseScreen();
      case EasyScreen.done:
        return DoseDoneScreen(
          slot: _recordedSlot ?? DoseSlot.dinner,
          onUndone: () => _goTo(EasyScreen.today),
        );
      case EasyScreen.record:
        return MedicationRecordScreen(
          onBackToToday: () => _goTo(EasyScreen.today),
        );
      case EasyScreen.heart:
        return const HeartScreen();
      case EasyScreen.medicines:
        return const MyMedicinesScreen();
      case EasyScreen.prescription:
        return PrescriptionScreen(
          onCompleted: (result) {
            _durResult = result;
            if (_hasPairConflict(result)) {
              _goTo(EasyScreen.interaction);
            } else {
              _goTo(EasyScreen.scheduleDays);
            }
          },
          onOpenScheduleDays: () => _goTo(EasyScreen.scheduleDays),
          onGoHome: () => _goTo(EasyScreen.today),
        );
      case EasyScreen.interaction:
        return DurAnalysisScreen(
          initialResult: _durResult,
          onOpenScheduleDays: () => _goTo(EasyScreen.scheduleDays),
          onGoHome: () => _goTo(EasyScreen.today),
        );
      case EasyScreen.scheduleDays:
        return ScheduleDaysScreen(onConfirmed: () => _goTo(EasyScreen.today));
      case EasyScreen.chat:
        return const PharmacistChatScreen();
      case EasyScreen.measure:
        return const MeasureScreen(returnToPreviousScreen: true);
      case EasyScreen.myInfo:
        return const MyPageScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showBar = showsEasyBar(_screen);
    final stepIndex = kEasyFlow.indexWhere((step) => step.screen == _screen);
    return Scaffold(
      backgroundColor: AppColors.bgTinted,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _EasyFlowTop(
              stepIndex: stepIndex,
              total: kEasyFlow.length,
              onMenu: _openMenu,
              onLeave: () =>
                  ref.read(appModeProvider.notifier).set(AppMode.normal),
            ),
            Expanded(
              child: KeyedSubtree(
                // 화면마다 새로 만든다. 보이지도 않는 화면이 센서를 잡고
                // 있지 않도록.
                key: ValueKey(_screen),
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: _buildScreen(),
                ),
              ),
            ),
          ],
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

/// 쉬운 화면 맨 위 — 지금 몇 걸음째인지와 일반 화면으로 나가는 길.
///
/// 시안은 걸음을 짧은 막대로 늘어놓고 오른쪽에 "1 / 8"을 적는다.
/// 막대만으로는 몇 걸음 남았는지 세기 어렵고, 숫자만으로는 얼마나 왔는지
/// 한눈에 안 보인다 — 둘을 함께 둔다.
class _EasyFlowTop extends StatelessWidget {
  final int stepIndex;
  final int total;
  final VoidCallback onMenu;
  final VoidCallback onLeave;

  const _EasyFlowTop({
    required this.stepIndex,
    required this.total,
    required this.onMenu,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    // 흐름에 없는 화면(약 설명 같은 곁가지)에서는 걸음을 세지 않는다.
    final counted = stepIndex >= 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              EasyMenuButton(onTap: onMenu),
              const Spacer(),
              _pill(onTap: onLeave, label: '일반 화면으로'),
            ],
          ),
          if (counted) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (int i = 0; i < total; i++) ...[
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: i <= stepIndex
                            ? AppColors.pointFill
                            : AppColors.secondaryFill,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (i != total - 1) const SizedBox(width: 6),
                ],
                const SizedBox(width: 12),
                Text(
                  '${stepIndex + 1} / $total',
                  style: AppText.cardTitle(size: 18, color: AppColors.point),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill({required VoidCallback onTap, required String label}) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: kCardShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  TablerIcons.arrows_exchange,
                  size: 22,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(label, style: AppText.cardTitle(size: 18)),
              ],
            ),
          ),
        ),
      ),
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
        border: Border(top: BorderSide(color: AppColors.chartPast, width: 1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.barShadow,
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
              // 시안 — 뒤로와 다음을 한 줄에 나란히. 뒤로는 검은 면으로
              // 두어 파란 "다음"과 헷갈리지 않게 한다.
              Row(
                children: [
                  if (onBack != null) ...[
                    SizedBox(
                      width: 128,
                      child: SeniorButton(
                        label: '뒤로',
                        icon: TablerIcons.arrow_left,
                        kind: SeniorButtonKind.dark,
                        minHeight: 76,
                        fontSize: 22,
                        radius: 20,
                        onPressed: onBack,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SeniorButton(
                      label: label,
                      minHeight: 76,
                      fontSize: 24,
                      radius: 20,
                      onPressed: onNext,
                    ),
                  ),
                ],
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

bool _hasPairConflict(Map<String, dynamic>? durResult) {
  const pairTypes = {'병용금기', '중복성분', '효능군중복'};
  final matches = durResult?['matches'];
  if (matches is! List) return false;
  return matches.any(
    (item) => item is Map && pairTypes.contains(item['type']?.toString()),
  );
}
