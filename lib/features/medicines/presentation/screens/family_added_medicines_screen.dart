import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../domain/display_policy.dart';
import '../../domain/user_medicine_models.dart';

/// 어르신 화면 — 가족이 약을 넣어드렸을 때 딱 한 번 뜨는 알림 화면.
///
/// **어르신이 할 일을 만들지 않는다.** 확인 버튼 하나만 있고, 그것도 "네,
/// 알겠어요"다. 자녀분 전화기에서 처방전을 찍었다는 사실과, 앞으로 소리로
/// 알려드린다는 사실만 말한다.
class FamilyAddedMedicinesScreen extends StatelessWidget {
  /// 약을 넣어준 가족 이름 — "김지안".
  final String guardianName;

  /// 그 가족을 부르는 말 — "딸". 모르면 빈 문자열.
  final String guardianRelation;

  /// 새로 들어온 약.
  final List<UserMedicine> medicines;

  /// "약 자세히 보기".
  final VoidCallback onOpenMedicines;

  const FamilyAddedMedicinesScreen({
    super.key,
    required this.guardianName,
    this.guardianRelation = '',
    required this.medicines,
    required this.onOpenMedicines,
  });

  /// "딸 김지안 님".
  String get _guardianTitle {
    final name = guardianName.trim();
    final relation = guardianRelation.trim();
    if (name.isEmpty) return relation.isEmpty ? '가족' : '$relation 님';
    return relation.isEmpty ? '$name 님' : '$relation $name 님';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorTitleHeader(title: '약이 들어왔어요'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeniorCard(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InitialAvatar(
                              name: guardianName,
                              size: 60,
                              background: AppColors.pointTint,
                              foreground: AppColors.point,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                '$_guardianTitle이\n약을 넣어드렸어요',
                                style: AppText.screenTitle(size: 26),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SeniorCard(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('새로 들어온 약', style: AppText.cardTitle(size: 21)),
                        const SizedBox(height: 14),
                        for (int i = 0; i < medicines.length; i++) ...[
                          if (i > 0) const SizedBox(height: 14),
                          _MedicineRow(medicine: medicines[i]),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeniorButton(
                    label: '네, 알겠어요',
                    minHeight: 74,
                    fontSize: 25,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 12),
                  SeniorButton(
                    label: '약 자세히 보기',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 64,
                    fontSize: 21,
                    onPressed: onOpenMedicines,
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

/// 약 한 줄 — 사진 자리 + 이름 + "한 번에 1정 · 아침 · 저녁".
class _MedicineRow extends StatelessWidget {
  final UserMedicine medicine;

  const _MedicineRow({required this.medicine});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const PillPhoto(size: 54),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stripExportAlias(medicine.displayName),
                style: AppText.cardTitle(size: 21),
              ),
              const SizedBox(height: 2),
              Text(doseLine(medicine), style: AppText.caption(size: 17.5)),
            ],
          ),
        ),
      ],
    );
  }

  /// "한 번에 1정 · 아침 · 저녁". 모르는 값은 지어내지 않고 그냥 뺀다.
  static String doseLine(UserMedicine medicine) {
    final parts = <String>[];
    final amount = medicine.amount.trim();
    if (amount.isNotEmpty) parts.add('한 번에 $amount');
    parts.addAll(slotLabels(medicine.administrationTimes));
    if (parts.isEmpty) return '드시는 때는 약 목록에서 볼 수 있어요';
    return parts.join(' · ');
  }

  /// 서버가 주는 시각("08:00")을 어르신이 쓰는 말로 옮긴다.
  /// 시각이 아니라 이미 "아침"처럼 온 값은 그대로 둔다.
  static List<String> slotLabels(List<String> times) {
    final labels = <String>[];
    for (final raw in times) {
      final text = raw.trim();
      if (text.isEmpty) continue;
      final hour = int.tryParse(text.split(':').first.trim());
      final label = hour == null
          ? text
          : hour < 11
          ? '아침'
          : hour < 17
          ? '점심'
          : '저녁';
      if (!labels.contains(label)) labels.add(label);
    }
    return labels;
  }
}
