import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/application/medication_controller.dart';
import '../../domain/drug_info.dart';
import 'drug_detail_screen.dart';

/// 20 · 내 약 목록.
///
/// 검색창을 두지 않는다. **지금 드시는 약**만 보여주고, 누르면 설명으로 간다.
/// 목록 한 줄. 서버가 준 약과, 우리가 가진 설명을 짝지은 것.
///
/// 설명이 없는 약도 목록에는 나온다. **드시는 약을 빼놓지 않는다** —
/// 설명이 없다고 목록에서 지우면 그 약은 없는 약이 된다.
@immutable
class MedicineEntry {
  /// 서버가 준 이름. 설명이 있으면 그쪽 이름을 쓴다.
  final String name;

  /// 효능 한 줄. 없으면 빈 문자열.
  final String effect;

  /// 언제·얼마나. 없으면 빈 문자열.
  final String schedule;

  /// 눌러서 볼 설명. 없으면 null.
  final DrugInfo? info;

  const MedicineEntry({
    required this.name,
    required this.effect,
    required this.schedule,
    required this.info,
  });
}

class MyMedicinesScreen extends ConsumerWidget {
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

  /// 오늘 드시는 약을 모아 설명과 짝짓는다.
  ///
  /// 같은 약이 아침·저녁에 나와도 목록에는 한 번만 올린다.
  List<MedicineEntry> _entries(WidgetRef ref) {
    final today = ref.watch(medicationProvider);
    final seen = <String>{};
    final entries = <MedicineEntry>[];
    final slotsOf = <String, List<String>>{};

    for (final dose in today.doses) {
      for (final medicine in dose.medicines) {
        slotsOf.putIfAbsent(medicine.ingredient, () => []).add(dose.slot.label);
      }
    }

    for (final dose in today.doses) {
      for (final medicine in dose.medicines) {
        if (!seen.add(medicine.ingredient)) continue;
        final info = DrugInfo.find(medicine.key ?? medicine.ingredient);
        final slots = slotsOf[medicine.ingredient] ?? const <String>[];
        entries.add(
          MedicineEntry(
            name: info?.name ?? medicine.ingredient,
            effect: medicine.effect ?? info?.effect ?? '',
            schedule: slots.isEmpty
                ? ''
                : '${slots.join('·')} · ${medicine.amount}',
            info: info,
          ),
        );
      }
    }

    // 서버가 아직 아무것도 안 줬으면 넘겨받은 목록을 쓴다.
    if (entries.isEmpty) {
      return [
        for (final drug in medicines)
          MedicineEntry(
            name: drug.name,
            effect: drug.effect,
            schedule: '${drug.when.replaceAll(' 드세요.', '')} · ${drug.dosage}',
            info: drug,
          ),
      ];
    }
    return entries;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = _entries(ref);
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
                    '지금 드시는 약 ${entries.length}가지 · 눌러서 설명 보기',
                    style: AppText.label(
                      size: 17.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final entry in entries) ...[
                    _MedicineCard(
                      entry: entry,
                      onTap: entry.info == null
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DrugDetailScreen(drug: entry.info!),
                                ),
                              ),
                    ),
                    const SizedBox(height: 10),
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
  final MedicineEntry entry;

  /// 설명이 없으면 null — 눌러도 열 것이 없다.
  final VoidCallback? onTap;

  const _MedicineCard({required this.entry, required this.onTap});

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
                Text(entry.name, style: AppText.cardTitle(size: 20)),
                if (entry.effect.isNotEmpty)
                  Text(
                    entry.effect,
                    style: AppText.label(size: 17.5, color: AppColors.point),
                  ),
                if (entry.schedule.isNotEmpty)
                  Text(entry.schedule, style: AppText.caption(size: 16.5)),
                // 설명이 없다고 목록에서 빼지 않는다. 대신 없다고 적는다.
                if (entry.info == null)
                  Text(
                    '설명은 아직 준비 중이에요',
                    style: AppText.caption(size: 16.5),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (entry.info != null) const SeniorChevron(),
        ],
      ),
    );
  }
}
