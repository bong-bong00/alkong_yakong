import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../domain/app_documents.dart';

/// 이용약관 · 개인정보처리방침처럼 긴 문서를 읽는 화면.
///
/// 쉬운 말 요약을 먼저 읽고, 그 아래에 조문을 둔다.
class PolicyScreen extends StatelessWidget {
  final AppDocument document;

  const PolicyScreen({super.key, required this.document});

  /// 이용약관.
  const PolicyScreen.terms({super.key}) : document = kTermsOfService;

  /// 개인정보처리방침.
  const PolicyScreen.privacy({super.key}) : document = kPrivacyPolicy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          SeniorBackHeader(title: document.title),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                // 쉬운 말 요약을 먼저 읽게 한다 (프로토타입 49번).
                for (final section in document.plain) ...[
                  const SizedBox(height: 12),
                  _SectionCard(section: section),
                ],
                if (document.plain.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text('자세한 약관', style: AppText.cardTitle(size: 20)),
                ],
                for (final section in document.sections) ...[
                  const SizedBox(height: 12),
                  _SectionCard(section: section),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final DocSection section;

  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(section.title, style: AppText.cardTitle(size: 20)),
          const SizedBox(height: 8),
          for (int i = 0; i < section.paragraphs.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _Paragraph(text: section.paragraphs[i]),
          ],
        ],
      ),
    );
  }
}

/// `· `로 시작하면 글머리표를 따로 세워 줄바꿈된 줄이 가지런히 들여쓰이게 한다.
class _Paragraph extends StatelessWidget {
  final String text;

  const _Paragraph({required this.text});

  @override
  Widget build(BuildContext context) {
    const bullet = '· ';
    if (!text.startsWith(bullet)) {
      return Text(text, style: AppText.body(size: 18));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('·', style: AppText.body(size: 18, weight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text.substring(bullet.length),
            style: AppText.body(size: 18),
          ),
        ),
      ],
    );
  }
}
