import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../application/user_medicines_controller.dart';
import '../../domain/user_medicine_models.dart';

/// 내 약 목록 — 활성 약 종류당 1행 (서버 `/medicines`).
class MyMedicinesScreen extends ConsumerWidget {
  const MyMedicinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicines = ref.watch(userMedicinesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorBackHeader(title: '내 약 목록', onBack: () => context.pop()),
          Expanded(
            child: medicines.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => RecoveryView(
                title: '약 목록을\n불러오지 못했어요',
                reassurance: '인터넷이나 서버가 잠깐 끊겼을 수 있어요. ',
                reassuranceEmphasis: '고장이 아니니 걱정하지 마세요.',
                steps: const ['잠시 후 다시 시도해 보세요', '와이파이나 데이터 연결을 확인해 보세요'],
                actionLabel: '다시 불러오기',
                onAction: () =>
                    ref.read(userMedicinesProvider.notifier).refresh(),
                stillWorksTitle: '지금도 할 수 있는 것',
                stillWorksBody: '오늘 홈에서 복약 기록과 처방전 사진 찍기는 그대로 쓸 수 있어요.',
              ),
              data: (items) => _MedicineList(items: items),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicineList extends StatelessWidget {
  final List<UserMedicine> items;

  const _MedicineList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SeniorCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(
                    TablerIcons.pill,
                    size: 42,
                    color: AppColors.point,
                  ),
                  const SizedBox(height: 14),
                  Text('등록된 약이 없어요', style: AppText.cardTitle(size: 22)),
                  const SizedBox(height: 8),
                  Text(
                    '처방전 사진을 찍으면 약을 확인한 뒤 등록할 수 있어요.',
                    textAlign: TextAlign.center,
                    style: AppText.body(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SeniorButton(
              label: '처방전 사진 찍기',
              onPressed: () => context.push('/prescription'),
            ),
          ],
        ),
      );
    }

    final active = items.where((item) => item.status == 'active').toList();
    final past = items.where((item) => item.status != 'active').toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Text(
          '등록한 약 ${items.length}가지',
          style: AppText.body(size: 19, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        if (active.isNotEmpty) ...[
          Text('현재 복용 중', style: AppText.cardTitle(size: 21)),
          const SizedBox(height: 10),
          for (final med in active) ...[
            _MedicineCard(medicine: med),
            const SizedBox(height: 10),
          ],
        ],
        if (past.isNotEmpty) ...[
          if (active.isNotEmpty) const SizedBox(height: 12),
          Text('이전에 등록한 약', style: AppText.cardTitle(size: 21)),
          const SizedBox(height: 10),
          for (final med in past) ...[
            _MedicineCard(medicine: med),
            const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 18),
        SeniorButton(
          label: '새 처방전 넣기',
          onPressed: () => context.push('/prescription'),
        ),
      ],
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final UserMedicine medicine;

  const _MedicineCard({required this.medicine});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      onTap: () => context.push('/medicines/${medicine.medicineCode}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _MedicineSummary(medicine: medicine)),
          const SizedBox(width: 12),
          Text(
            medicine.dosageLabel,
            style: AppText.cardTitle(size: 19, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 4),
          const SeniorChevron(),
        ],
      ),
    );
  }
}

class _MedicineSummary extends StatelessWidget {
  final UserMedicine medicine;

  const _MedicineSummary({required this.medicine});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          medicine.displayName,
          style: AppText.label(size: 20, color: AppColors.textBody),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (medicine.ingredientLabel.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '주성분: ${medicine.ingredientLabel}',
            style: AppText.caption(color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (medicine.cardSpoken != null) ...[
          const SizedBox(height: 4),
          Text(
            medicine.cardSpoken!,
            style: AppText.caption(color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
