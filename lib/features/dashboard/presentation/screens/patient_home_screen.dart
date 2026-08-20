import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../../core/widgets/week_date_strip.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medication/domain/medication_models.dart';
import '../../../medication/presentation/widgets/dose_guard_sheets.dart';

/// 3a — 오늘 · 홈.
///
/// 앱을 열었을 때 "지금 무엇을 먹어야 하는가" 하나만 보이게 한다.
/// "지금 드실 약" 카드가 시선을 독점하고 나머지는 아래로 밀린다.
/// 약은 사진 없이 성분명으로 부르고, 포인트색은 오늘 날짜·활성 탭·
/// 핵심 버튼·완료 체크 네 자리에만 쓴다.
class PatientHomeScreen extends ConsumerStatefulWidget {
  /// 기록 탭으로 이동 (지난 날짜 칩을 눌렀을 때).
  final VoidCallback? onOpenRecord;

  /// 심장 박동 화면으로 이동.
  final VoidCallback? onOpenHeartbeat;

  /// 사용자 이름 — 상단 아바타의 첫 글자로 쓴다.
  final String userName;

  const PatientHomeScreen({
    super.key,
    this.onOpenRecord,
    this.onOpenHeartbeat,
    this.userName = '김복자',
  });

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  /// 방금 기록한 시간대. null이 아니면 4b 완료 화면을 그린다.
  DoseSlot? _justCompleted;

  /// "30분 뒤에 다시"로 밀린 시각.
  DateTime? _snoozedUntil;

  Future<void> _onTake(DoseEntry dose) async {
    final controller = ref.read(medicationProvider.notifier);
    final outcome = controller.take(dose.slot);

    switch (outcome) {
      case DoseCheckOutcome.recorded:
        setState(() {
          _justCompleted = dose.slot;
          _snoozedUntil = null;
        });
      case DoseCheckOutcome.alreadyTaken:
        await showDuplicateDoseSheet(
          context: context,
          dose: ref.read(medicationProvider).doseOf(dose.slot),
          onUndo: () => _onUndo(dose.slot),
        );
      case DoseCheckOutcome.tooLate:
        final tookAnyway = await showLateDoseSheet(
          context: context,
          slot: dose.slot,
        );
        if (!tookAnyway) return;
        controller.takeAnyway(dose.slot);
        if (!mounted) return;
        setState(() {
          _justCompleted = dose.slot;
          _snoozedUntil = null;
        });
    }
  }

  void _onUndo(DoseSlot slot) {
    ref.read(medicationProvider.notifier).undo(slot);
    setState(() => _justCompleted = null);
  }

  void _onSnooze(DoseEntry dose) {
    final until = ref.read(medicationProvider.notifier).snooze(dose.slot);
    setState(() => _snoozedUntil = until);
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(medicationProvider);
    final now = DateTime.now();
    final completedSlot = _justCompleted;

    return Column(
      children: [
        _Header(
          today: now,
          userName: widget.userName,
          onSelectDate: (date) {
            if (date.day != now.day) widget.onOpenRecord?.call();
          },
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (completedSlot != null)
                  ..._completedCards(today, completedSlot)
                else
                  ..._todayCards(today),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 평소 상태 (3a) ────────────────────────────────────────────
  List<Widget> _todayCards(TodayMedication today) {
    final next = today.nextDose;
    return [
      if (_snoozedUntil != null) ...[
        _SnoozeNotice(until: _snoozedUntil!),
        const SizedBox(height: 12),
      ],
      if (next != null)
        _NextDoseCard(
          dose: next,
          onTake: () => _onTake(next),
          onSnooze: () => _onSnooze(next),
        )
      else
        _AllDoneCard(
          today: today,
          onTapSlot: (slot) => _onTake(today.doseOf(slot)),
        ),
      if (today.takenCount > 0 && next != null) ...[
        const SizedBox(height: 12),
        _TakenSummaryCard(today: today),
      ],
      const SizedBox(height: 12),
      _HeartbeatCard(today: today, onTap: widget.onOpenHeartbeat),
    ];
  }

  // ── 먹었어요 누른 뒤 (4b) ──────────────────────────────────────
  List<Widget> _completedCards(TodayMedication today, DoseSlot slot) {
    final controller = ref.read(medicationProvider.notifier);
    return [
      SeniorCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.pointTint,
                shape: BoxShape.circle,
              ),
              child: Text(
                '✓',
                style: AppText.screenTitle(size: 38, color: AppColors.point),
              ),
            ),
            const SizedBox(height: 14),
            Text('잘하셨어요', style: AppText.screenTitle()),
            const SizedBox(height: 6),
            Text(
              today.allTaken
                  ? '${slot.label} 약 다 드신 것으로 기록했어요. 오늘 ${today.doses.length}번 모두 완료.'
                  : '${slot.label} 약 다 드신 것으로 기록했어요.',
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            // 되돌리기는 시간 제한 없이 노출한다 — 시니어는 실수를 늦게 발견한다.
            SeniorButton(
              label: '잘못 눌렀어요 · 되돌리기',
              kind: SeniorButtonKind.secondary,
              minHeight: 60,
              fontSize: 20,
              onPressed: () => _onUndo(slot),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SeniorCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('오늘 복약', style: AppText.cardTitle()),
            const SizedBox(height: 12),
            _SlotChips(today: today),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (controller.guardianNotifiedFor(slot))
        SeniorCard(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            children: [
              InitialAvatar(
                name: today.guardianName,
                size: 44,
                background: AppColors.bg,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '${today.guardianTitle}에게 알려드렸어요',
                  style: AppText.label(
                    size: 18.5,
                    color: AppColors.textBody,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

// ════════════════════════════════════════════════════════════════
//  상단 바 (A형) — 날짜 pill + 아바타 + 주간 스트립
// ════════════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  final DateTime today;
  final String userName;
  final ValueChanged<DateTime> onSelectDate;

  const _Header({
    required this.today,
    required this.userName,
    required this.onSelectDate,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${today.month}월 ${today.day}일',
                        style: AppText.cardTitle(
                          size: 21,
                          color: AppColors.point,
                        ),
                      ),
                      Text('오늘', style: AppText.cardTitle(size: 21)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InitialAvatar(name: userName),
            ],
          ),
          const SizedBox(height: 14),
          WeekDateStrip(today: today, onSelect: onSelectDate),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  카드들
// ════════════════════════════════════════════════════════════════

/// "30분 뒤에 다시" 를 누른 뒤 상단에 남는 안내. 절대시간으로 알려준다.
class _SnoozeNotice extends StatelessWidget {
  final DateTime until;
  const _SnoozeNotice({required this.until});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.pointTint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        '${DoseSlot.absoluteTime(until)}에 다시 알려드려요',
        style: AppText.label(size: 19, color: AppColors.point),
      ),
    );
  }
}

/// 카드 1 — 지금 드실 약.
class _NextDoseCard extends StatelessWidget {
  final DoseEntry dose;
  final VoidCallback onTake;
  final VoidCallback onSnooze;

  const _NextDoseCard({
    required this.dose,
    required this.onTake,
    required this.onSnooze,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Dot(),
              const SizedBox(width: 10),
              Expanded(
                child: Text('지금 드실 약', style: AppText.label(size: 18)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 고정 폭을 주지 않는다 — 글자가 커져도 "저녁 6 / 시"로 깨지면 안 된다.
          Text(dose.slot.spokenTime, style: AppText.bigTime(size: 38)),
          const SizedBox(height: 12),
          for (int i = 0; i < dose.medicines.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 8),
              const SeniorDivider(),
              const SizedBox(height: 8),
            ],
            _MedicineRow(medicine: dose.medicines[i]),
          ],
          const SizedBox(height: 12),
          SeniorButton(label: '먹었어요', onPressed: onTake),
          SeniorTextButton(label: '30분 뒤에 다시 알려주기', onPressed: onSnooze),
        ],
      ),
    );
  }
}

class _MedicineRow extends StatelessWidget {
  final Medicine medicine;
  const _MedicineRow({required this.medicine});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: medicine.spoken,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              medicine.ingredient,
              style: AppText.label(size: 20, color: AppColors.textBody),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            medicine.amount,
            style: AppText.cardTitle(size: 19, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 카드 2 — 완료 요약.
class _TakenSummaryCard extends StatelessWidget {
  final TodayMedication today;
  const _TakenSummaryCard({required this.today});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(today.takenSummary, style: AppText.cardTitle()),
                Text(
                  '오늘 ${today.doses.length}번 중 ${today.takenCount}번 완료',
                  style: AppText.caption(size: 17),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.pointTint,
              shape: BoxShape.circle,
            ),
            child: Text(
              '✓',
              style: AppText.cardTitle(size: 20, color: AppColors.point),
            ),
          ),
        ],
      ),
    );
  }
}

/// 오늘 세 번을 모두 기록한 상태.
/// 시간대 칩을 다시 누르면 5f 중복 복용 차단 시트가 뜬다.
class _AllDoneCard extends StatelessWidget {
  final TodayMedication today;
  final ValueChanged<DoseSlot> onTapSlot;

  const _AllDoneCard({required this.today, required this.onTapSlot});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('오늘 약 다 드셨어요', style: AppText.screenTitle(size: 24)),
          const SizedBox(height: 6),
          Text(
            '다음 약은 내일 ${today.doses.first.slot.spokenTime}에 알려드릴게요.',
            style: AppText.body(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          _SlotChips(today: today, onTapSlot: onTapSlot),
        ],
      ),
    );
  }
}

/// 아침·점심·저녁 3등분 칩.
class _SlotChips extends StatelessWidget {
  final TodayMedication today;
  final ValueChanged<DoseSlot>? onTapSlot;

  const _SlotChips({required this.today, this.onTapSlot});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < today.doses.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _SlotChip(dose: today.doses[i], onTap: onTapSlot)),
        ],
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  final DoseEntry dose;
  final ValueChanged<DoseSlot>? onTap;

  const _SlotChip({required this.dose, this.onTap});

  @override
  Widget build(BuildContext context) {
    final taken = dose.taken;
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(dose.slot),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: taken ? AppColors.pointTint : AppColors.bg,
          borderRadius: BorderRadius.circular(16),
          border: taken
              ? null
              : Border.all(color: AppColors.strongBorder, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dose.slot.label,
              style: AppText.label(
                size: 18,
                color: taken ? AppColors.point : AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              taken ? '✓' : '·',
              style: AppText.cardTitle(
                size: 20,
                color: taken ? AppColors.point : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 카드 3 — 심장 박동.
class _HeartbeatCard extends StatelessWidget {
  final TodayMedication today;
  final VoidCallback? onTap;

  const _HeartbeatCard({required this.today, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '심장 박동 ${today.heartRate} · '
                  '${today.heartRateNormal ? '정상' : '확인 필요'}',
                  style: AppText.cardTitle(),
                ),
                Text(
                  '${today.guardianTitle}이 함께 보고 있어요',
                  style: AppText.caption(size: 17),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const SeniorChevron(),
        ],
      ),
    );
  }
}
