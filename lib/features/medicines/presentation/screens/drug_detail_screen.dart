import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../application/user_medicines_controller.dart';
import '../../domain/display_policy.dart';
import '../../domain/user_medicine_models.dart';

/// 내 약 한 종류 상세 — 서버 쉬운말·주의·복용 정보.
class DrugDetailScreen extends ConsumerStatefulWidget {
  final String medicineCode;

  const DrugDetailScreen({super.key, required this.medicineCode});

  @override
  ConsumerState<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends ConsumerState<DrugDetailScreen> {
  UserMedicine? _medicine;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final med = await ref
          .read(userMedicinesProvider.notifier)
          .loadDetail(widget.medicineCode);
      if (!mounted) return;
      setState(() {
        _medicine = med;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorBackHeader(
            title: '약 자세히',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? RecoveryView(
                    title: '약 정보를\n불러오지 못했어요',
                    reassurance: '잠시 연결이 끊겼을 수 있어요. ',
                    reassuranceEmphasis: '고장이 아니니 걱정하지 마세요.',
                    steps: const ['다시 시도해 보세요'],
                    actionLabel: '다시 불러오기',
                    onAction: _load,
                    stillWorksTitle: '지금도 할 수 있는 것',
                    stillWorksBody: '오늘 홈에서 복약 기록은 그대로 쓸 수 있어요.',
                  )
                : _DetailBody(medicine: _medicine!),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final UserMedicine medicine;

  const _DetailBody({required this.medicine});

  @override
  Widget build(BuildContext context) {
    final ingredients = ingredientParts(medicine.ingredientName);
    final cautions = [
      if ((medicine.keyCaution ?? '').trim().isNotEmpty) medicine.keyCaution!,
      ...medicine.keyCautions.where(
        (c) => c.trim().isNotEmpty && c != medicine.keyCaution,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SeniorCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicine.displayName,
                  style: AppText.screenTitle(size: 24),
                ),
                if (ingredients.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('주성분', style: AppText.label(size: 17)),
                  const SizedBox(height: 4),
                  for (int index = 0; index < ingredients.length; index++)
                    Text(
                      '${ingredients.length > 1 ? '· ' : ''}${ingredients[index]}${index == 0 && medicine.ingredientStrength.trim().isNotEmpty ? ' · ${medicine.ingredientStrength.trim()}' : ''}',
                      style: AppText.caption(
                        size: 17,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
                if (medicine.cardSpoken != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    medicine.cardSpoken!,
                    style: AppText.body(size: 19, color: AppColors.textBody),
                  ),
                ],
                if (medicine.easyPurposes.any(isCardPurposeLabel)) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final purpose in medicine.easyPurposes)
                        if (isCardPurposeLabel(purpose))
                          _TagChip(label: purpose),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (cautions.isNotEmpty) ...[
            const SizedBox(height: 12),
            SeniorCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconTitle(
                    icon: TablerIcons.alert_triangle,
                    color: AppColors.danger,
                    text: '꼭 기억해 주세요',
                    style: AppText.cardTitle(color: AppColors.danger),
                  ),
                  const SizedBox(height: 12),
                  for (final caution in cautions) ...[
                    Text(
                      '· $caution',
                      style: AppText.body(size: 18, color: AppColors.textBody),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SeniorCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTitle(
                  icon: medicine.interactionStatus == 'risk_found'
                      ? TablerIcons.alert_triangle
                      : TablerIcons.pills,
                  color: medicine.interactionStatus == 'risk_found'
                      ? AppColors.danger
                      : AppColors.point,
                  text: _interactionTitle(medicine.interactionStatus),
                  style: AppText.cardTitle(
                    color: medicine.interactionStatus == 'risk_found'
                        ? AppColors.danger
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  medicine.interactionSummary ?? '아직 함께먹기 검사를 하지 않았어요.',
                  style: AppText.body(size: 18),
                ),
                if (medicine.interactionStatus == 'risk_found') ...[
                  if (medicine.interactionConflictNames.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '관련 약: ${medicine.interactionConflictNames.join(' · ')}',
                      style: AppText.label(size: 17),
                    ),
                  ],
                  if (medicine.interactionRiskLevel.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '위험 수준: ${_riskLevelLabel(medicine.interactionRiskLevel)}',
                      style: AppText.label(size: 17, color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '함께 복용하기 전에 의사나 약사에게 확인해 주세요.',
                    style: AppText.label(size: 17, color: AppColors.danger),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SeniorCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTitle(
                  icon: TablerIcons.clock,
                  text: '복용 방법',
                  style: AppText.cardTitle(),
                ),
                const SizedBox(height: 12),
                Text(
                  '한 번에 ${medicine.doseAction} 양 ${medicine.dosageLabel}',
                  style: AppText.body(size: 19),
                ),
                const SizedBox(height: 6),
                Text(medicine.frequencyLabel, style: AppText.body(size: 19)),
                if (medicine.administrationTimes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '시간: ${medicine.administrationTimes.join(' · ')}',
                    style: AppText.caption(size: 17),
                  ),
                ],
              ],
            ),
          ),
          if ((medicine.purposeNotice ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            SeniorCard(
              padding: const EdgeInsets.all(20),
              child: Text(
                medicine.purposeNotice!,
                style: AppText.caption(color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _interactionTitle(String status) {
    return switch (status) {
      'risk_found' => '함께먹기 주의가 있어요',
      'none' => '확인된 상호작용이 없어요',
      'check_needed' => '함께먹기 확인이 필요해요',
      _ => '함께먹기 검사 전이에요',
    };
  }

  static String _riskLevelLabel(String level) {
    return switch (level.toUpperCase()) {
      'HIGH' => '높음',
      'MEDIUM' => '주의',
      'LOW' => '낮음',
      _ => '확인 필요',
    };
  }
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.pointTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: AppText.caption(size: 16, color: AppColors.point),
      ),
    );
  }
}
