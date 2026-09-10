import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/mode_badge.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medication/domain/medication_models.dart';
import '../../../medication/presentation/widgets/dose_flow_sheets.dart';
import '../../../medication/presentation/widgets/dose_guard_sheets.dart';

/// 12 / 15 · 오늘 · 홈.
///
/// **주인공은 "지금 드실 약" 하나.** 나머지는 아래로 밀린다.
class PatientHomeScreen extends ConsumerStatefulWidget {
  /// 기록 탭으로 이동.
  final VoidCallback? onOpenRecord;

  /// 심박수 관리 화면으로 이동.
  final VoidCallback? onOpenHeartbeat;

  /// 약 목록 · AI 약사 · 처방전 넣기로 이동.
  final VoidCallback? onOpenMedicines;
  final VoidCallback? onOpenChat;
  final VoidCallback? onOpenPrescription;

  /// 약 하나를 눌렀을 때 설명 화면으로.
  final void Function(Medicine medicine)? onOpenDrug;

  /// "먹었어요" 뒤 심박수를 재러 갈 때.
  final VoidCallback? onMeasure;

  /// 복약을 기록한 뒤 완료 화면으로.
  final VoidCallback? onDone;

  const PatientHomeScreen({
    super.key,
    this.onOpenRecord,
    this.onOpenHeartbeat,
    this.onOpenMedicines,
    this.onOpenChat,
    this.onOpenPrescription,
    this.onOpenDrug,
    this.onMeasure,
    this.onDone,
  });

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  /// 재알림을 미뤘을 때 상단에 뜨는 안내.
  String? _snoozeNotice;

  @override
  void initState() {
    super.initState();
    // 잔여일이 0이면 홈에 들어오는 순간 리필 시트를 연다. 하루 한 번만.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskRefill());
  }

  Future<void> _maybeAskRefill() async {
    final controller = ref.read(medicationProvider.notifier);
    if (!mounted || !controller.shouldAskRefill) return;
    controller.markRefillAsked();

    final choice = await showRefillSheet(
      context,
      startedOn: '8월 12일',
      totalDays: 21,
    );
    if (!mounted) return;
    switch (choice) {
      case RefillChoice.addPrescription:
        widget.onOpenPrescription?.call();
      case RefillChoice.tellFamily:
        showSeniorSnackbar(
          context,
          '${ref.read(medicationProvider).guardianTitle}에게 알렸어요',
        );
      case RefillChoice.askTomorrow:
        break;
    }
  }

  /// "먹었어요" — 바로 기록하지 않고 센서 착용부터 묻는다.
  Future<void> _take(DoseSlot slot) async {
    final controller = ref.read(medicationProvider.notifier);

    // 이미 기록된 시간대는 묻기 전에 막는다. 사후 안내가 아니라 사전 차단이다.
    if (ref.read(medicationProvider).doseOf(slot).taken) {
      await _showDuplicateGuard(slot);
      return;
    }

    final choice = await showWearSensorSheet(context);
    if (!mounted || choice == WearChoice.cancel) return;

    final outcome = controller.take(slot);
    if (!mounted) return;

    switch (outcome) {
      case DoseCheckOutcome.alreadyTaken:
        await _showDuplicateGuard(slot);
      case DoseCheckOutcome.tooLate:
        final proceed = await showLateDoseSheet(context: context, slot: slot);
        if (proceed && mounted) {
          controller.takeAnyway(slot);
          _afterRecord(choice);
        }
      case DoseCheckOutcome.recorded:
        _afterRecord(choice);
    }
  }

  void _afterRecord(WearChoice choice) {
    if (choice == WearChoice.wearingAndMeasure) {
      widget.onMeasure?.call();
    } else {
      widget.onDone?.call();
    }
  }

  Future<void> _showDuplicateGuard(DoseSlot slot) async {
    final dose = ref.read(medicationProvider).doseOf(slot);
    await showDuplicateDoseSheet(
      context: context,
      dose: dose,
      onUndo: () => ref.read(medicationProvider.notifier).undo(slot),
    );
  }

  void _snooze(DoseSlot slot) {
    final until = ref.read(medicationProvider.notifier).snooze(slot);
    setState(
      () => _snoozeNotice = '${DoseSlot.absoluteTime(until)}에 다시 알려드려요',
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(medicationProvider);
    final next = today.nextDose;
    final now = DateTime.now();

    return Column(
      children: [
        _Header(userName: '김복자', date: now),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_snoozeNotice != null) ...[
                  _SnoozeNotice(text: _snoozeNotice!),
                  const SizedBox(height: 12),
                ],
                if (next != null)
                  _NextDoseCard(
                    today: today,
                    dose: next,
                    onTake: () => _take(next.slot),
                    onSnooze: () => _snooze(next.slot),
                    onOpenDrug: widget.onOpenDrug,
                    onDaysTap: () =>
                        ref.read(medicationProvider.notifier).decrementDaysLeft(),
                  )
                else
                  _AllDoneCard(
                    today: today,
                    onReTake: () => _take(DoseSlot.dinner),
                    onOpenDrug: widget.onOpenDrug,
                    onDaysTap: () =>
                        ref.read(medicationProvider.notifier).decrementDaysLeft(),
                  ),
                const SizedBox(height: 12),
                _ProgressRow(today: today, onOpenRecord: widget.onOpenRecord),
                const SizedBox(height: 12),
                _ShortcutGrid(
                  heartRate: today.heartRate,
                  onOpenMedicines: widget.onOpenMedicines,
                  onOpenHeartbeat: widget.onOpenHeartbeat,
                  onOpenChat: widget.onOpenChat,
                  onOpenPrescription: widget.onOpenPrescription,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 날짜 칩 + 모드 배지 + 아바타.
class _Header extends StatelessWidget {
  final String userName;
  final DateTime date;

  const _Header({required this.userName, required this.date});

  @override
  Widget build(BuildContext context) {
    return SeniorHeader(
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${date.month}월 ${date.day}일',
                    style: AppText.cardTitle(
                      size: 21,
                      color: AppColors.point,
                      weight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '오늘',
                    style: AppText.cardTitle(size: 21, weight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          const ModeBadge(),
          const SizedBox(width: 10),
          InitialAvatar(name: userName, size: 52, background: AppColors.bg),
        ],
      ),
    );
  }
}

class _SnoozeNotice extends StatelessWidget {
  final String text;
  const _SnoozeNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.pointTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppText.label(size: 18.5, color: AppColors.pointInk),
      ),
    );
  }
}

/// 지금 드실 약 — 이 화면의 주인공.
class _NextDoseCard extends StatelessWidget {
  final TodayMedication today;
  final DoseEntry dose;
  final VoidCallback onTake;
  final VoidCallback onSnooze;
  final void Function(Medicine)? onOpenDrug;
  final VoidCallback onDaysTap;

  const _NextDoseCard({
    required this.today,
    required this.dose,
    required this.onTake,
    required this.onSnooze,
    required this.onOpenDrug,
    required this.onDaysTap,
  });

  @override
  Widget build(BuildContext context) {
    final others = today.doses.where((d) => d.slot != dose.slot).toList();
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DaysLeftRow(
            daysLeft: today.daysLeft,
            phrase: today.daysLeftPhrase,
            onTap: onDaysTap,
          ),
          const SizedBox(height: 12),
          LabelValueRow(
            label: Text(
              dose.slot.spokenTime,
              style: AppText.bigTime(size: 36),
            ),
            value: Text(
              '눌러서 설명 보기',
              textAlign: TextAlign.right,
              style: AppText.label(size: 16.5, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < dose.medicines.length; i++) ...[
            if (i > 0) const SeniorDivider(),
            _MedicineRow(
              medicine: dose.medicines[i],
              onTap: onOpenDrug == null
                  ? null
                  : () => onOpenDrug!(dose.medicines[i]),
            ),
          ],
          const SizedBox(height: 12),
          SeniorButton(label: '먹었어요', onPressed: onTake),
          const SizedBox(height: 10),
          SeniorButton(
            label: '30분 뒤에 다시 알려주기',
            kind: SeniorButtonKind.secondary,
            minHeight: 62,
            fontSize: 20,
            onPressed: onSnooze,
          ),
          if (others.any((d) => d.taken)) ...[
            const SizedBox(height: 12),
            _OtherDosesBlock(doses: others.where((d) => d.taken).toList()),
          ],
        ],
      ),
    );
  }
}

/// 약 한 줄 — 사진, 이름, 효능, 생김새, 개수.
class _MedicineRow extends StatelessWidget {
  final Medicine medicine;
  final VoidCallback? onTap;

  const _MedicineRow({required this.medicine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            _PillPhoto(size: 60),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(medicine.ingredient, style: AppText.cardTitle(size: 21)),
                  if (medicine.effect != null)
                    Text(
                      medicine.effect!,
                      style: AppText.label(size: 18, color: AppColors.point),
                    ),
                  if (medicine.appearance != null)
                    Text(
                      medicine.appearance!,
                      style: AppText.caption(size: 17),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              medicine.amount,
              style: AppText.cardTitle(size: 20, color: AppColors.point),
            ),
          ],
        ),
      ),
    );
  }
}

/// 약 사진 자리. 실제 의약품 이미지가 들어오면 여기를 바꾼다.
class _PillPhoto extends StatelessWidget {
  final double size;
  const _PillPhoto({required this.size});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.bg,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border, width: 2),
        ),
        child: Icon(
          TablerIcons.pill,
          size: size * 0.45,
          color: AppColors.inactive,
        ),
      ),
    );
  }
}

/// 오늘 이미 드신 다른 약.
class _OtherDosesBlock extends StatelessWidget {
  final List<DoseEntry> doses;
  const _OtherDosesBlock({required this.doses});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('오늘 다른 약', style: AppText.label(size: 17.5)),
          const SizedBox(height: 10),
          for (final dose in doses)
            for (final medicine in dose.medicines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const _PillPhoto(size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medicine.ingredient,
                            style: AppText.label(
                              size: 18,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (medicine.effect != null)
                            Text(
                              medicine.effect!,
                              style: AppText.caption(size: 16.5),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${dose.slot.label} ✓',
                      style: AppText.cardTitle(
                        size: 16.5,
                        color: AppColors.point,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// 오늘 약을 다 드신 뒤의 카드.
class _AllDoneCard extends StatelessWidget {
  final TodayMedication today;
  final VoidCallback onReTake;
  final void Function(Medicine)? onOpenDrug;
  final VoidCallback onDaysTap;

  const _AllDoneCard({
    required this.today,
    required this.onReTake,
    required this.onOpenDrug,
    required this.onDaysTap,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.pointTint,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  '✓',
                  style: AppText.cardTitle(size: 20, color: AppColors.point),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('오늘 약 다 드셨어요', style: AppText.cardTitle(size: 22)),
                    Text(
                      '다음 약은 내일 아침 8시',
                      style: AppText.caption(size: 17.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DaysLeftRow(
            daysLeft: today.daysLeft,
            phrase: today.daysLeftPhrase,
            onTap: onDaysTap,
          ),
          const SizedBox(height: 12),
          SeniorButton(
            label: '저녁 약 다시 누르기',
            kind: SeniorButtonKind.neutral,
            minHeight: 60,
            fontSize: 19,
            onPressed: onReTake,
          ),
        ],
      ),
    );
  }
}

/// 오늘 몇 번 드셨는지 — 점 셋과 한 문장.
class _ProgressRow extends StatelessWidget {
  final TodayMedication today;
  final VoidCallback? onOpenRecord;

  const _ProgressRow({required this.today, required this.onOpenRecord});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      onTap: onOpenRecord,
      child: Row(
        children: [
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final dose in today.doses) ...[
                  Container(
                    width: 11,
                    height: 11,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: dose.taken
                          ? AppColors.point
                          : AppColors.strongBorder,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              today.allTaken
                  ? '세 번 다 드셨어요'
                  : '오늘 ${today.doses.length}번 중 ${today.takenCount}번 드셨어요',
              style: AppText.label(size: 18, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '기록 ›',
            style: AppText.cardTitle(size: 18, color: AppColors.point),
          ),
        ],
      ),
    );
  }
}

/// 2×2 바로가기.
class _ShortcutGrid extends StatelessWidget {
  final int heartRate;
  final VoidCallback? onOpenMedicines;
  final VoidCallback? onOpenHeartbeat;
  final VoidCallback? onOpenChat;
  final VoidCallback? onOpenPrescription;

  const _ShortcutGrid({
    required this.heartRate,
    required this.onOpenMedicines,
    required this.onOpenHeartbeat,
    required this.onOpenChat,
    required this.onOpenPrescription,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Shortcut(
                  icon: TablerIcons.pill,
                  label: '내 약 목록',
                  onTap: onOpenMedicines,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Shortcut(
                  icon: TablerIcons.activity_heartbeat,
                  label: '심박수',
                  trailing: '$heartRate',
                  onTap: onOpenHeartbeat,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Shortcut(
                  icon: TablerIcons.message_circle_question,
                  label: 'AI 약사 상담',
                  onTap: onOpenChat,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Shortcut(
                  icon: TablerIcons.prescription,
                  label: '처방전 넣기',
                  onTap: onOpenPrescription,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;

  const _Shortcut({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.pointTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: ExcludeSemantics(
              child: Icon(icon, size: 26, color: AppColors.point),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text(label, style: AppText.cardTitle(size: 19))),
              if (trailing != null)
                Text(
                  trailing!,
                  style: AppText.cardTitle(size: 23, color: AppColors.point),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
