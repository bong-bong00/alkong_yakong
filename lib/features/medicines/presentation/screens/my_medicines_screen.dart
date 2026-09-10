import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../domain/drug_info.dart';
import 'drug_detail_screen.dart';

/// 20 · 내 약 목록.
///
/// 검색창을 두지 않는다. **지금 드시는 약**만 보여주고, 누르면 설명으로 간다.
class MyMedicinesScreen extends StatelessWidget {
  final List<DrugInfo> medicines;

  /// 알림 시간 설정으로 가는 길.
  final VoidCallback? onOpenAlarm;

  /// 새 처방전 넣기.
  final VoidCallback? onAddPrescription;

  /// 지금 설정된 알림 시각 — "아침 8시, 저녁 6시".
  final String alarmSummary;

  const MyMedicinesScreen({
    super.key,
    this.medicines = DrugInfo.all,
    this.onOpenAlarm,
    this.onAddPrescription,
    this.alarmSummary = '아침 8시, 저녁 6시',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '내 약 목록'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '지금 드시는 약 ${medicines.length}가지 · 눌러서 설명 보기',
                    style: AppText.label(
                      size: 17.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final drug in medicines) ...[
                    _MedicineCard(
                      drug: drug,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DrugDetailScreen(drug: drug),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 17,
                    ),
                    onTap: onOpenAlarm,
                    child: Row(
                      children: [
                        const ExcludeSemantics(
                          child: Icon(
                            TablerIcons.alarm,
                            size: 26,
                            color: AppColors.point,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '알림 시간 바꾸기',
                                style: AppText.cardTitle(size: 19),
                              ),
                              Text(
                                '지금 · $alarmSummary',
                                style: AppText.caption(size: 17),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const SeniorChevron(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SeniorButton(
                    label: '새 처방전 넣기',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 66,
                    fontSize: 21,
                    onPressed: onAddPrescription,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final DrugInfo drug;
  final VoidCallback onTap;

  const _MedicineCard({required this.drug, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      onTap: onTap,
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.bg,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 2),
              ),
              child: const Icon(
                TablerIcons.pill,
                size: 28,
                color: AppColors.inactive,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(drug.name, style: AppText.cardTitle(size: 20)),
                Text(
                  drug.effect,
                  style: AppText.label(size: 17.5, color: AppColors.point),
                ),
                Text(
                  '${drug.when.replaceAll(' 드세요.', '')} · ${drug.dosage}',
                  style: AppText.caption(size: 16.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const SeniorChevron(),
        ],
      ),
    );
  }
}
