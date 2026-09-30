import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/senior_card.dart';
import '../../medication/application/medication_controller.dart';
import '../../medication/domain/medication_models.dart';

/// 쉬운 화면 · 약 드실 시간 (시안 70).
///
/// 일반 화면의 오늘 홈과 다른 화면이다. 쉬운 화면에는 고를 것이 없다 —
/// 이번에 드실 약만 늘어놓고, 다음 걸음은 아래 바가 맡는다.
class EasyDoseScreen extends ConsumerWidget {
  const EasyDoseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(medicationProvider);
    final next = today.nextDose;
    final medicines = next?.medicines ?? const <Medicine>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (next == null) ...[
            Text('오늘 약을 다 드셨어요', style: AppText.screenTitle(size: 28)),
            const SizedBox(height: 8),
            Text(
              '이제 쉬셔도 돼요.',
              style: AppText.body(size: 20, color: AppColors.textSecondary),
            ),
          ] else ...[
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${next.slot.label} 약 ',
                    style: AppText.screenTitle(
                      size: 28,
                    ).copyWith(fontWeight: FontWeight.w500),
                  ),
                  TextSpan(
                    text: '드실 시간이에요',
                    style: AppText.screenTitle(size: 28),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '약 드시기 전에 심박부터 재요',
              style: AppText.body(size: 20, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            SeniorCard(
              radius: 26,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  for (int i = 0; i < medicines.length; i++) ...[
                    if (i > 0) const SeniorDivider(),
                    _EasyMedicineRow(medicine: medicines[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 약 한 줄 — 사진 · 이름과 생김새 · 몇 알.
class _EasyMedicineRow extends StatelessWidget {
  final Medicine medicine;

  const _EasyMedicineRow({required this.medicine});

  @override
  Widget build(BuildContext context) {
    final look = medicine.appearance?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          const PillPhoto(size: 60),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(medicine.displayName, style: AppText.cardTitle(size: 22)),
                if (look.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    look,
                    style: AppText.body(
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            medicine.amount,
            style: AppText.cardTitle(size: 22, color: AppColors.point),
          ),
        ],
      ),
    );
  }
}
