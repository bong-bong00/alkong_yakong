import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../domain/planned_medication.dart';

/// 미래 일정은 읽기 전용이다. 기존 오늘/지난날 기록 카드는 바꾸지 않는다.
class PlannedMedicationDetail extends StatelessWidget {
  final String dayLabel;
  final List<PlannedMedicationSlot> slots;
  final bool loading;
  final bool failed;
  const PlannedMedicationDetail({
    super.key,
    required this.dayLabel,
    required this.slots,
    this.loading = false,
    this.failed = false,
  });

  @override
  Widget build(BuildContext context) => SeniorCard(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(dayLabel, style: AppText.cardTitle(size: 20)),
        const SizedBox(height: 8),
        Text(
          loading
              ? '복약 일정을 불러오고 있어요'
              : failed
              ? '복약 일정을 불러오지 못했어요'
              : slots.isEmpty
              ? '복약 일정이 없어요'
              : '복약 예정 ${slots.length}회',
          style: AppText.caption(size: 17.5),
        ),
        if (!loading && !failed)
          for (final slot in slots) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    slot.slot == '복약' ? '복약' : '${slot.slot} 약',
                    style: AppText.label(size: 19),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      children: [
                        Text(slot.time, style: AppText.label(size: 18)),
                        const SizedBox(width: 8),
                        Text(
                          '예정',
                          style: AppText.caption(
                            size: 16,
                            color: AppColors.point,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            for (final medicine in slot.medicines) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(medicine.name, style: AppText.body(size: 18)),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      medicine.amount,
                      textAlign: TextAlign.end,
                      style: AppText.body(size: 18),
                    ),
                  ),
                ],
              ),
            ],
          ],
      ],
    ),
  );
}
