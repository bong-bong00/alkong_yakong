import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/mode/app_mode.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/senior_button.dart';
import '../../../core/widgets/senior_card.dart';
import '../../../dev_mock.dart';
import '../../biosignal/presentation/screens/heart_screen.dart';
import '../../biosignal/presentation/screens/measure_screen.dart';
import '../../dashboard/presentation/screens/medication_record_screen.dart';
import 'easy_dose_flow.dart';
import '../../medication/domain/medication_models.dart';
import '../../medication/presentation/screens/dose_done_screen.dart';
import '../../medicines/presentation/screens/my_medicines_screen.dart';
import '../../drug_explain/drug_explain_screen.dart';
import '../../prescription/presentation/screens/prescription_screen.dart';
import '../../prescription/presentation/screens/schedule_days_screen.dart';
import '../../profile/presentation/screens/mypage_screen.dart';
import '../domain/easy_flow.dart';

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

  /// 방금 기록한 시간대. 완료 화면이 저녁이라고 우기지 않게 들고 있는다.
  DoseSlot? _recordedSlot;

  /// 지나온 화면. "이전"에서 하나씩 꺼낸다.
  final List<EasyScreen> _history = <EasyScreen>[];

  void _goTo(EasyScreen screen) {
    if (screen == EasyScreen.chat) {
      context.push('/drug-explain');
      return;
    }
    if (screen == _screen) return;
    setState(() {
      _history.add(_screen);
      if (_history.length > 40) _history.removeAt(0);
      _screen = screen;
    });
  }

  void _back() {
    if (_history.isEmpty) {
      // 돌아갈 길이 없으면 오늘로. 단추가 죽어 갔힐 곳이 없으면 안 된다.
      _goTo(EasyScreen.today);
      return;
    }
    setState(() => _screen = _history.removeLast());
  }

  /// 일반 모드가 쓰는 화면을 그대로 부른다.
  Widget _buildScreen() {
    switch (_screen) {
      case EasyScreen.today:
        // 명세서 76~85. 약 드실 시간 → 가슴 띠 → 먹기 전 재기 → 약 드시기
        // → 먹은 후 재기 → 결과 → 오늘 다 했어요를 한 걸음씩 지난다.
        return EasyDoseFlow(
          onOpenMedicines: () => _goTo(EasyScreen.medicines),
          onOpenRecord: () => _goTo(EasyScreen.record),
          onOpenHeart: () => _goTo(EasyScreen.heart),
          onOpenMyInfo: () => _goTo(EasyScreen.myInfo),
          onOpenChat: () => _goTo(EasyScreen.chat),
        );
      case EasyScreen.done:
        return DoseDoneScreen(
          slot: _recordedSlot ?? DoseSlot.dinner,
          onUndone: () => _goTo(EasyScreen.today),
        );
      case EasyScreen.record:
        return MedicationRecordScreen(
          onBackToToday: () => _goTo(EasyScreen.today),
          compactTop: true,
        );
      case EasyScreen.heart:
        return HeartScreen(repository: mockHeartRepository());
      case EasyScreen.medicines:
        return const MyMedicinesScreen(compactTop: true);
      case EasyScreen.prescription:
        return PrescriptionScreen(
          onCompleted: (_) => _goTo(EasyScreen.scheduleDays),
          onOpenScheduleDays: () => _goTo(EasyScreen.scheduleDays),
          onGoHome: () => _goTo(EasyScreen.today),
        );
      case EasyScreen.scheduleDays:
        return ScheduleDaysScreen(onConfirmed: () => _goTo(EasyScreen.today));
      case EasyScreen.chat:
        return const DrugExplainScreen();
      case EasyScreen.measure:
        return const MeasureScreen(returnToPreviousScreen: true);
      case EasyScreen.myInfo:
        return const MyPageScreen(compactTop: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showBar = showsEasyBar(_screen);
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _EasyFlowTop(
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
              // 메뉴에서 들어온 화면에는 돌아가는 길 하나면 된다.
              onBack: _back,
            )
          : null,
    );
  }
}

/// 간편 화면 맨 위 — 메뉴와 일반 화면으로 나가는 길.
///
/// 걸음 막대는 여기서 그리지 않는다. 명세서는 복약 한 바퀴(76~84)에서만
/// 여덟 칸 막대를 두고, 나머지 간편 화면(85~90)에는 두지 않는다.
class _EasyFlowTop extends StatelessWidget {
  final VoidCallback onLeave;

  const _EasyFlowTop({required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
      child: Row(
        children: [
          const Spacer(),
          _pill(onTap: onLeave, label: '일반 화면으로'),
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
  final VoidCallback onBack;

  const _EasyFlowBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.chartPast, width: 1)),
        // 명세서 86~90: 위로 1px 선 하나와 넓은 그림자.
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
              // 뒤로와 다음을 한 줄에 나란히. 뒤로는 일반 화면과 같은
              // 회색 면으로 둔다 — 같은 뜻의 단추가 화면마다 다른 색이면
              // 다른 것으로 읽힌다.
              SeniorButton(
                label: '뒤로',
                kind: SeniorButtonKind.secondary,
                minHeight: 72,
                fontSize: 21,
                radius: 18,
                onPressed: onBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
