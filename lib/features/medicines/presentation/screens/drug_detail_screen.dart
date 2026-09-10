import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../domain/drug_info.dart';
import 'pharmacist_chat_screen.dart';

/// 21 · 약 설명.
///
/// 검색 없이 **내가 먹는 약부터** 설명한다.
/// 위험 안내는 맨 아래에 따로 두어, 읽다가 겁먹고 멈추지 않게 한다.
class DrugDetailScreen extends StatelessWidget {
  final DrugInfo drug;

  /// 함께먹기 주의로 가는 길.
  final VoidCallback? onOpenInteraction;

  const DrugDetailScreen({
    super.key,
    required this.drug,
    this.onOpenInteraction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorBackHeader(title: drug.name),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SummaryCard(drug: drug),
                  const SizedBox(height: 12),
                  _WhatCard(text: drug.what),
                  const SizedBox(height: 12),
                  _Section(
                    title: '언제 어떻게 드세요',
                    body: drug.when,
                    boxed: drug.withMeal,
                  ),
                  const SizedBox(height: 12),
                  _Section(
                    title: '이런 게 있을 수 있어요',
                    body: drug.sideEffects,
                  ),
                  const SizedBox(height: 12),
                  _WarningCard(text: drug.warning),
                  const SizedBox(height: 16),
                  SeniorButton(
                    label: '이 약, AI 약사 상담',
                    minHeight: 66,
                    fontSize: 22,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PharmacistChatScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SeniorButton(
                    label: '함께먹기 주의 보기',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 62,
                    fontSize: 20,
                    onPressed: onOpenInteraction,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '약사님이 확인한 설명이에요',
                    textAlign: TextAlign.center,
                    style: AppText.caption(size: 17),
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

class _SummaryCard extends StatelessWidget {
  final DrugInfo drug;
  const _SummaryCard({required this.drug});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.bg,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 2),
              ),
              child: const Icon(
                TablerIcons.pill,
                size: 34,
                color: AppColors.inactive,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(drug.name, style: AppText.cardTitle(size: 22)),
                Text(
                  drug.effect,
                  style: AppText.label(size: 19, color: AppColors.point),
                ),
                Text(
                  '${drug.appearance} · ${drug.dosage}',
                  style: AppText.caption(size: 17.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 무슨 약이에요? — 이 화면에서 가장 먼저 읽혀야 하는 것.
class _WhatCard extends StatelessWidget {
  final String text;
  const _WhatCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.pointTint,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '무슨 약이에요?',
            style: AppText.cardTitle(size: 18, color: AppColors.point),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: AppText.body(
              size: 21,
              color: AppColors.textPrimary,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  /// 카드 안 한 단계 더 들어간 블록에 담을 보조 안내.
  final String? boxed;

  const _Section({required this.title, required this.body, this.boxed});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.cardTitle(size: 20)),
          const SizedBox(height: 10),
          Text(
            body,
            style: AppText.body(
              size: 19.5,
              color: AppColors.textBody,
              weight: FontWeight.w700,
            ),
          ),
          if (boxed != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.sunken,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(boxed!, style: AppText.body(size: 18)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 이럴 때는 바로 알려주세요 — 주의 테두리를 두른다.
class _WarningCard extends StatelessWidget {
  final String text;
  const _WarningCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      borderColor: AppColors.dangerBorder,
      borderWidth: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이럴 때는 바로 알려주세요',
            style: AppText.cardTitle(size: 19, color: AppColors.danger),
          ),
          const SizedBox(height: 8),
          Text(text, style: AppText.body(size: 19)),
        ],
      ),
    );
  }
}
