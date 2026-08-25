import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/mode/app_mode.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/senior_button.dart';
import '../../biosignal/presentation/screens/heartbeat_screen.dart';
import '../../dashboard/presentation/screens/medication_record_screen.dart';
import '../../dashboard/presentation/screens/patient_home_screen.dart';
import '../../dur_analysis/presentation/screens/dur_analysis_screen.dart';
import '../../prescription/presentation/screens/prescription_screen.dart';
import '../../profile/presentation/screens/mypage_screen.dart';
import '../domain/easy_flow.dart';

/// 쉬운 모드 쉘.
///
/// 화면은 일반 모드와 **완전히 같은 것**을 부른다. 다른 것은 두 가지뿐이다.
/// 1. 아래 탭 대신 "다음" 버튼 하나가 있고, 화면이 한 줄로 이어진다.
/// 2. 지금 몇 번째인지 점으로 보여준다.
///
/// 순서는 [kEasyFlow]가 정한다. 순서를 바꿀 때 이 파일은 고치지 않는다.
class EasyFlowShell extends ConsumerStatefulWidget {
  const EasyFlowShell({super.key});

  @override
  ConsumerState<EasyFlowShell> createState() => _EasyFlowShellState();
}

class _EasyFlowShellState extends ConsumerState<EasyFlowShell> {
  int _index = 0;

  EasyStep get _step => kEasyFlow[_index];

  void _next() {
    setState(() {
      // 마지막 단계에서 누르면 처음으로 돌아간다. 끝나서 막히는 곳이 없다.
      _index = (_index + 1) % kEasyFlow.length;
    });
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index -= 1);
  }

  void _jumpTo(EasyScreen screen) {
    final target = kEasyFlow.indexWhere((s) => s.screen == screen);
    if (target >= 0) setState(() => _index = target);
  }

  /// 일반 모드가 쓰는 화면을 그대로 부른다.
  Widget _buildScreen() {
    switch (_step.screen) {
      case EasyScreen.today:
        return PatientHomeScreen(
          onOpenRecord: () => _jumpTo(EasyScreen.record),
          onOpenHeartbeat: () => _jumpTo(EasyScreen.heartbeat),
        );
      case EasyScreen.prescription:
        // 등록이 끝나면 손대지 않아도 다음 화면으로 넘어간다.
        return PrescriptionScreen(onCompleted: _next);
      case EasyScreen.interaction:
        return const DurAnalysisScreen();
      case EasyScreen.record:
        return const MedicationRecordScreen();
      case EasyScreen.heartbeat:
        return const HeartbeatScreen();
      case EasyScreen.myInfo:
        return const MyPageScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: KeyedSubtree(
        // 단계마다 새로 만든다. 심박 화면이 보이지도 않는데 센서를 잡고 있는
        // 일이 없도록, 지나간 화면은 남겨두지 않는다.
        key: ValueKey(_step.screen),
        child: _buildScreen(),
      ),
      bottomNavigationBar: _EasyFlowBar(
        index: _index,
        total: kEasyFlow.length,
        step: _step,
        onNext: _next,
        onBack: _index == 0 ? null : _back,
        onLeave: () =>
            ref.read(appModeProvider.notifier).set(AppMode.normal),
      ),
    );
  }
}

class _EasyFlowBar extends StatelessWidget {
  final int index;
  final int total;
  final EasyStep step;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onLeave;

  const _EasyFlowBar({
    required this.index,
    required this.total,
    required this.step,
    required this.onNext,
    required this.onBack,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.headerBg,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 지금 몇 번째인지 ──
              Row(
                children: [
                  _StepDots(index: index, total: total),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$total단계 중 ${index + 1}번째',
                      style: AppText.caption(size: 17),
                    ),
                  ),
                  // 막다른 곳이 없도록 나가는 길을 항상 열어 둔다.
                  Semantics(
                    button: true,
                    child: InkWell(
                      onTap: onLeave,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: Text(
                          '일반 모드로',
                          style: AppText.label(
                            size: 17,
                            color: AppColors.point,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (step.hint != null) ...[
                const SizedBox(height: 2),
                Text(step.hint!, style: AppText.caption(size: 17)),
              ],
              const SizedBox(height: 10),
              SeniorButton(label: step.nextLabel, onPressed: onNext),
              if (onBack != null)
                SeniorTextButton(label: '이전으로', onPressed: onBack),
            ],
          ),
        ),
      ),
    );
  }
}

/// 진행 점. 지나온 단계는 채워지고, 지금 단계는 길쭉해진다.
class _StepDots extends StatelessWidget {
  final int index;
  final int total;

  const _StepDots({required this.index, required this.total});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Container(
              width: i == index ? 22 : 9,
              height: 9,
              decoration: BoxDecoration(
                color: i <= index ? AppColors.point : AppColors.chipBg,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
