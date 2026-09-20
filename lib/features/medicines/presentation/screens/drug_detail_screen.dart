import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/mode/app_mode.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/senior_button.dart';
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
    final easyMode = ref.watch(appModeProvider).isEasy;
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
                : _DetailBody(medicine: _medicine!, easyMode: easyMode),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final UserMedicine medicine;
  final bool easyMode;

  const _DetailBody({required this.medicine, required this.easyMode});

  @override
  Widget build(BuildContext context) {
    final ingredients = ingredientParts(medicine.ingredientName);
    final cautions = <String>[
      if ((medicine.keyCaution ?? '').trim().isNotEmpty) medicine.keyCaution!,
      ...medicine.keyCautions.where(
        (c) => c.trim().isNotEmpty && c != medicine.keyCaution,
      ),
    ].where((text) => _isPersonCaution(text)).take(3).toList();

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PillPhoto(size: 58),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medicine.displayName,
                            style: AppText.screenTitle(size: 24),
                          ),
                          if (medicine.manufacturer.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '제조사: ${medicine.manufacturer}',
                              style: AppText.caption(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
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
          if (medicine.hasDetailContent) ...[
            if (medicine.ingredientExplanation.trim().isNotEmpty ||
                medicine.approvedUseSummary.trim().isNotEmpty ||
                medicine.approvedUses.isNotEmpty) ...[
              const SizedBox(height: 12),
              SeniorCard(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('이 약은 무슨 일을 하나요?', style: AppText.cardTitle(size: 21)),
                    if (medicine.ingredientExplanation.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _Keyworded(
                        text: medicine.ingredientExplanation,
                        extra: medicine.easyPurposes,
                      ),
                    ],
                    if (medicine.approvedUseSummary.trim().isNotEmpty ||
                        medicine.approvedUses.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1, color: AppColors.border),
                      const SizedBox(height: 16),
                      if (medicine.approvedUseSummary.trim().isNotEmpty)
                        _Keyworded(
                          text: medicine.approvedUseSummary,
                          extra: medicine.easyPurposes,
                        ),
                      for (final purpose in medicine.approvedUses) ...[
                        const SizedBox(height: 8),
                        _Keyworded(
                          text: '· $purpose',
                          extra: medicine.easyPurposes,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        '실제 처방 이유는 의료진에게 확인해 주세요.',
                        // 본문에 딸린 각주다. 읽을 사람은 읽되 본문을 가리지 않게.
                        style: AppText.caption(size: 14.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            SeniorCard(
              padding: const EdgeInsets.all(20),
              child: Text(
                _detailStatusMessage(medicine.detailStatus),
                style: AppText.body(size: 18, color: AppColors.textSecondary),
              ),
            ),
          ],
          if (cautions.isNotEmpty) ...[
            const SizedBox(height: 12),
            SeniorCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '꼭 기억해 주세요',
                    style: AppText.cardTitle(size: 21, color: AppColors.danger),
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
          if (medicine.interactionStatus == 'risk_found' &&
              (medicine.interactionSummary ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            SeniorCard(
              padding: const EdgeInsets.all(22),
              borderColor: AppColors.danger,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '함께먹기 주의가 있어요',
                    style: AppText.cardTitle(size: 21, color: AppColors.danger),
                  ),
                  const SizedBox(height: 10),
                  if (medicine.interactionPairLabel.trim().isNotEmpty) ...[
                    Text(
                      _pairLine(medicine.interactionPairLabel),
                      style: AppText.cardTitle(size: 19),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    medicine.interactionSummary!,
                    style: AppText.body(size: 18),
                  ),
                  if (!medicine.interactionSummary!.contains('확인해')) ...[
                    const SizedBox(height: 8),
                    Text(
                      '약국이나 병원에 한 번 확인해 주세요.',
                      style: AppText.label(size: 17, color: AppColors.danger),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SeniorButton(
            label: '이 약, AI 약사 상담',
            onPressed: () => context.push('/drug-explain'),
          ),
          if (medicine.detailSourceName.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('정보 출처 · 식약처 의약품 허가정보', style: AppText.caption(size: 15)),
          ],
        ],
      ),
    );
  }

  /// "가↔️나"를 "가 + 나"로 읽어 준다.
  static String _pairLine(String raw) => raw
      .replaceAll('↔️', '+')
      .replaceAll('↔', '+')
      .replaceAll('  ', ' ')
      .trim();

  static bool _isPersonCaution(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    if (value.contains('사용상의주의')) return false;
    if (value.contains('투여하지 말')) return false;
    if (value.contains('신중히 투여')) return false;
    return true;
  }

  static String _detailStatusMessage(String status) {
    return switch (status.toUpperCase()) {
      'FAILED' => '자세한 설명을 불러오지 못했지만 제품 기본 정보는 볼 수 있어요.',
      'OUTDATED' => '기존 안전 정보는 볼 수 있어요. 최신 공식 정보로 갱신 중이에요.',
      'NEEDS_REVIEW' => '공식 정보에서 안전하게 정리한 기본 설명을 보여드려요.',
      _ => '현재 확인할 수 있는 제품 기본 정보를 보여드려요.',
    };
  }
}

/// 본문에서 눈에 먼저 들어와야 하는 낱말들.
///
/// 어르신은 문장을 처음부터 끝까지 읽지 않고 아는 낱말을 먼저 찾는다.
/// "무슨 병에 쓰는 약인지"가 그 낱말이라 굵게·파랗게 칠한다.
const List<String> _keyTerms = [
  '제2형 당뇨',
  '제1형 당뇨',
  '당뇨',
  '고혈압',
  '저혈압',
  '고지혈증',
  '이상지질혈증',
  '부정맥',
  '협심증',
  '심부전',
  '심근경색',
  '뇌졸중',
  '혈전',
  '천식',
  '기관지염',
  '폐렴',
  '위염',
  '위궤양',
  '역류성 식도염',
  '속쓰림',
  '변비',
  '설사',
  '관절염',
  '골다공증',
  '통풍',
  '갑상선',
  '전립선',
  '녹내장',
  '백내장',
  '빈혈',
  '치매',
  '우울',
  '불안',
  '불면',
  '알레르기',
  '두드러기',
  '염증',
  '통증',
  '열',
  '혈당',
  '혈압',
  '콜레스테롤',
];

/// 핵심 낱말만 굵게 칠한 한 문단.
class _Keyworded extends StatelessWidget {
  final String text;

  /// 이 약에만 해당하는 낱말(쉬운 효능 딱지)도 함께 칠한다.
  final List<String> extra;

  const _Keyworded({required this.text, this.extra = const []});

  /// 긴 낱말부터 찾아야 "당뇨"가 "제2형 당뇨"를 잘라먹지 않는다.
  List<String> get _terms {
    final terms = <String>{
      ..._keyTerms,
      for (final item in extra)
        if (item.trim().length >= 2) item.trim(),
    }.toList();
    terms.sort((a, b) => b.length.compareTo(a.length));
    return terms;
  }

  @override
  Widget build(BuildContext context) {
    final base = AppText.body(size: 18);
    final strong = AppText.body(
      size: 18,
      color: AppColors.point,
      weight: FontWeight.w700,
    );
    final spans = <TextSpan>[];
    final terms = _terms;
    var index = 0;
    while (index < text.length) {
      String? hit;
      for (final term in terms) {
        if (text.startsWith(term, index)) {
          hit = term;
          break;
        }
      }
      if (hit == null) {
        // 평범한 글자는 앞의 조각에 붙인다.
        if (spans.isNotEmpty && spans.last.style == base) {
          spans[spans.length - 1] = TextSpan(
            text: '${spans.last.text}${text[index]}',
            style: base,
          );
        } else {
          spans.add(TextSpan(text: text[index], style: base));
        }
        index += 1;
      } else {
        spans.add(TextSpan(text: hit, style: strong));
        index += hit.length;
      }
    }
    return Text.rich(TextSpan(children: spans));
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
