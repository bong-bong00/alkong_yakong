import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../application/medication_controller.dart';
import '../../domain/medication_models.dart';

/// 14 · 복약 완료.
///
/// 기록됐다는 것을 분명히 알리고, **시간 제한 없이** 되돌릴 수 있게 둔다.
/// 시니어는 잘못 누른 것을 한참 뒤에 발견한다.
class DoseDoneScreen extends ConsumerWidget {
  /// 방금 기록한 시간대.
  final DoseSlot slot;

  /// 되돌린 뒤 돌아갈 곳.
  final VoidCallback? onUndone;

  const DoseDoneScreen({super.key, required this.slot, this.onUndone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(medicationProvider);
    final dose = today.doseOf(slot);

    return Column(
      children: [
        SeniorHeader(
          child: Row(
            children: [
              Expanded(
                child: Text('복약 기록', style: AppText.screenTitle(size: 24)),
              ),
              InitialAvatar(
                name: '김복자',
                size: 52,
                background: AppColors.bg,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dose.taken)
                  _SuccessCard(
                    slot: slot,
                    allTaken: today.allTaken,
                    onUndo: () {
                      ref.read(medicationProvider.notifier).undo(slot);
                      onUndone?.call();
                    },
                  )
                else
                  _PendingCard(slot: slot),
                const SizedBox(height: 12),
                _TodayStrip(today: today),
                const SizedBox(height: 12),
                _GuardianCard(
                  guardianTitle: today.guardianTitle,
                  taken: dose.taken,
                  slotLabel: slot.label,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final DoseSlot slot;
  final bool allTaken;
  final VoidCallback onUndo;

  const _SuccessCard({
    required this.slot,
    required this.allTaken,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
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
              style: AppText.hero(size: 38, color: AppColors.point),
            ),
          ),
          const SizedBox(height: 14),
          Text('잘하셨어요', style: AppText.screenTitle(size: 28)),
          const SizedBox(height: 8),
          Text(
            allTaken
                ? '${slot.label} 약 다 드신 것으로\n기록했어요. 오늘 3번 모두 완료.'
                : '${slot.label} 약 다 드신 것으로\n기록했어요.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 19, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SeniorButton(
            label: '잘못 눌렀어요 · 되돌리기',
            kind: SeniorButtonKind.neutral,
            minHeight: 60,
            fontSize: 20,
            onPressed: onUndo,
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final DoseSlot slot;
  const _PendingCard({required this.slot});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.bg,
              shape: BoxShape.circle,
            ),
            child: const ExcludeSemantics(
              child: Icon(
                TablerIcons.clock,
                size: 40,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${slot.label} 약이 남아 있어요',
            style: AppText.screenTitle(size: 28),
          ),
        ],
      ),
    );
  }
}

/// 아침·점심·저녁 3분할.
class _TodayStrip extends StatelessWidget {
  final TodayMedication today;
  const _TodayStrip({required this.today});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('오늘 복약', style: AppText.cardTitle()),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < today.doses.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: _SlotChip(dose: today.doses[i])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final DoseEntry dose;
  const _SlotChip({required this.dose});

  @override
  Widget build(BuildContext context) {
    final taken = dose.taken;
    return Semantics(
      label: '${dose.slot.label} ${taken ? '드셨어요' : '아직 안 드셨어요'}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: taken ? AppColors.pointTint : AppColors.bg,
            borderRadius: BorderRadius.circular(16),
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
              const SizedBox(height: 2),
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
      ),
    );
  }
}

class _GuardianCard extends StatelessWidget {
  final String guardianTitle;
  final bool taken;
  final String slotLabel;

  const _GuardianCard({
    required this.guardianTitle,
    required this.taken,
    required this.slotLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      child: Row(
        children: [
          InitialAvatar(name: guardianTitle, size: 44, background: AppColors.bg),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              taken
                  ? '$guardianTitle에게 알려드렸어요'
                  : '$slotLabel 약을 누르면 $guardianTitle에게 전해져요',
              style: AppText.label(size: 18.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
