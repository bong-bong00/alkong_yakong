import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/medicine_flow_colors.dart';
import '../../../../core/mode/app_mode.dart';
import '../../../../core/theme/medicine_flow_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/medicine_flow_card.dart' hide PillPhoto;
import '../../../../core/widgets/senior_card.dart' show PillPhoto;
import '../../../../core/widgets/senior_header.dart';
import '../../application/user_medicines_controller.dart';
import '../../domain/display_policy.dart';
import '../../domain/user_medicine_models.dart';
import '../../domain/official_purpose_layout.dart';

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

  /// 지금 보고 있는 탭. 0 하는 일 · 1 주의 · 2 먹는 법.
  ///
  /// 한 화면에 다 쌓으면 아래쪽은 끝까지 안 내려가 안 읽힌다. 주의사항이
  /// 그 아래에 묻히는 것이 가장 나쁘다.
  int _tab = 0;

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
                : _DetailBody(
                    medicine: _medicine!,
                    easyMode: easyMode,
                    tab: _tab,
                    onTabChanged: (index) => setState(() => _tab = index),
                  ),
          ),
          // 읽다가 모르는 것이 생기면 그 자리에서 물어보게 한다. 약 이름을
          // 다시 고르게 하지 않는다 — 지금 보고 있는 약이 곧 그 약이다.
          if (!_loading && _error == null && _medicine != null)
            _AskAboutThisDrug(name: _medicine!.displayName),
        ],
      ),
    );
  }
}

/// 약 자세히 맨 아래 주 버튼. 누르면 이 약을 고른 채로 알콩이가 열린다.
class _AskAboutThisDrug extends StatelessWidget {
  final String name;

  const _AskAboutThisDrug({required this.name});

  @override
  Widget build(BuildContext context) {
    final short = nameWithoutStrength(name);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: SafeArea(
        top: false,
        child: Semantics(
          button: true,
          label: '$short 물어보기',
          child: GestureDetector(
            onTap: () => context.push('/drug-explain', extra: name),
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minHeight: 76),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.point,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '이 약 물어보기',
                    style: AppText.cardTitle(size: 22, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '알콩이가 $short만 보고 답해요',
                    style: AppText.caption(
                      size: 16,
                      color: AppColors.onPointMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfficialPurposeText extends StatelessWidget {
  final String purpose;

  const _OfficialPurposeText({required this.purpose});

  @override
  Widget build(BuildContext context) {
    final layout = OfficialPurposeLayout.fromText(purpose);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (layout.heading.isNotEmpty) ...[
          Text(layout.heading, style: AppText.cardTitle(size: 20)),
          const SizedBox(height: 6),
        ],
        Text('· ${layout.body}', style: AppText.body(size: 20)),
      ],
    );
  }
}

class _DetailBody extends StatelessWidget {
  final UserMedicine medicine;
  final bool easyMode;

  /// 0 하는 일 · 1 주의.
  final int tab;
  final ValueChanged<int> onTabChanged;

  const _DetailBody({
    required this.medicine,
    required this.easyMode,
    required this.tab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
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
          _ProfileCard(medicine: medicine),
          const SizedBox(height: 14),
          // 하는 일 · 주의 둘로 가른다. 먹는 법은 "어떤 치료에 쓰이나요" 바로
          // 아래가 제자리다 — 무슨 약인지 읽고 나면 다음에 궁금한 것이
          // 어떻게 먹느냐이기 때문이다.
          SeniorSegmented(
            labels: const ['하는 일', '주의'],
            index: tab,
            onChanged: onTabChanged,
          ),
          const SizedBox(height: 14),
          if (tab == 0)
            _WhatItDoesTab(medicine: medicine, easyMode: easyMode)
          else
            _CautionTab(medicine: medicine, cautions: cautions),
          // 출처는 박스에 담지 않는다. 읽을 거리가 아니라 꼬리말이다.
          if (medicine.detailSourceName.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              '정보 출처 · 식약처 의약품 허가정보',
              style: AppText.caption(size: 17, color: AppColors.textSecondary),
            ),
          ],
          if ((medicine.purposeNotice ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              medicine.purposeNotice!,
              style: AppText.caption(size: 17, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  static bool _isPersonCaution(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    if (value.contains('사용상의주의')) return false;
    return true;
  }
}

/// 상세 설명을 못 불러왔을 때 대신 적는 말.
String _detailStatusMessage(String status) {
  return switch (status.toUpperCase()) {
    'FAILED' => '자세한 설명을 불러오지 못했지만 제품 기본 정보는 볼 수 있어요.',
    'OUTDATED' => '기존 안전 정보는 볼 수 있어요. 최신 공식 정보로 갱신 중이에요.',
    'NEEDS_REVIEW' => '공식 정보에서 안전하게 정리한 기본 설명을 보여드려요.',
    _ => '현재 확인할 수 있는 제품 기본 정보를 보여드려요.',
  };
}

/// 맨 위 약 프로필 — 사진 · 이름 · 제조사 · 주성분 · 한 줄 설명.
///
/// 아래에 "주성분 설명" 칸을 따로 두지 않는다. 같은 말을 두 번 읽게 된다.
class _ProfileCard extends StatelessWidget {
  final UserMedicine medicine;

  const _ProfileCard({required this.medicine});

  /// 이 약이 무슨 일을 하는지 한 문장. 검토된 쉬운말을 먼저 쓰고,
  /// 없으면 성분 설명을 쓴다. **두 가지를 같이 적지 않는다** — 같은 말을
  /// 두 번 읽게 된다.
  String get _explanation {
    // 원문을 그대로 보여 준다. 앞뒤 공백까지 손대면 서버가 보낸 글과
    // 화면의 글이 달라져, 어디서 바뀐 것인지 따라가기 어려워진다.
    final spoken = medicine.detailSpoken ?? '';
    if (spoken.trim().isNotEmpty) return spoken;
    return medicine.ingredientExplanation;
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = ingredientParts(medicine.ingredientName);
    final strength = medicine.ingredientStrength.trim();
    return SeniorCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PillPhoto(size: 72, imageUrl: medicine.imageUrl),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicine.displayName,
                      style: AppText.screenTitle(size: 26),
                    ),
                    if (ingredients.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          ingredients.first,
                          if (strength.isNotEmpty) strength,
                        ].join(' · '),
                        style: AppText.body(
                          size: 19,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (ingredients.length > 1)
                        Text(
                          '외 ${ingredients.length - 1}가지 성분',
                          style: AppText.caption(
                            size: 17,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                    if (medicine.manufacturer.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        medicine.manufacturer,
                        style: AppText.caption(
                          size: 17,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_explanation.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _EmphasizedBodyText(
              text: _explanation,
              highlight: medicine.ingredientHighlight,
              ingredient: medicine.ingredientName,
              fallbackHighlight: medicine.approvedUseSummary,
            ),
          ],
          if (medicine.easyPurposes.any(isCardPurposeLabel)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final purpose in medicine.easyPurposes)
                  if (isCardPurposeLabel(purpose)) _TagChip(label: purpose),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 하는 일 탭 — 어떤 치료에 쓰이는지, 그리고 어떻게 먹는지.
class _WhatItDoesTab extends StatelessWidget {
  final UserMedicine medicine;
  final bool easyMode;

  const _WhatItDoesTab({required this.medicine, required this.easyMode});

  @override
  Widget build(BuildContext context) {
    final seenUses = <String>{};
    final extraOfficialUses = medicine.allApprovedUses.where((purpose) {
      final normalized = purpose.trim();
      return normalized.isNotEmpty &&
          normalized != medicine.approvedUseSummary.trim() &&
          !medicine.approvedUses.any((shown) => shown.trim() == normalized) &&
          // 같은 줄이 두 번 오면 한 번만 읽게 둔다.
          seenUses.add(normalized);
    }).toList();
    final hasUses =
        medicine.treatmentUses.isNotEmpty ||
        medicine.approvedUseSummary.trim().isNotEmpty ||
        medicine.approvedUses.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!medicine.hasDetailContent)
          SeniorCard(
            padding: const EdgeInsets.all(20),
            child: Text(
              _detailStatusMessage(medicine.detailStatus),
              style: AppText.body(size: 20, color: AppColors.textSecondary),
            ),
          )
        else if (hasUses)
          SeniorCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTitle(
                  icon: Icons.medical_information_outlined,
                  text: '어떤 치료에 쓰이나요?',
                  style: AppText.cardTitle(size: 22),
                ),
                const SizedBox(height: 12),
                if (medicine.treatmentUses.isNotEmpty)
                  for (final use in medicine.treatmentUses) ...[
                    // 제목과 설명을 한 흐름으로 쓴다. 제목만 따로 떼어
                    // 놓으면 "혈전이 생기기 쉬운 / 분"처럼 끊겨 읽힌다.
                    _UseLine(use: use),
                    const SizedBox(height: 10),
                  ]
                else ...[
                  if (medicine.approvedUseSummary.trim().isNotEmpty)
                    Text(
                      medicine.approvedUseSummary,
                      style: AppText.body(size: 20),
                    ),
                  for (final purpose in medicine.approvedUses) ...[
                    const SizedBox(height: 8),
                    Text('· $purpose', style: AppText.body(size: 20)),
                  ],
                ],
                const SizedBox(height: 4),
                Text(
                  '실제 처방 이유는 의료진에게 확인해 주세요.',
                  style: AppText.caption(
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _DoseWayCard(medicine: medicine, easyMode: easyMode),
        if (extraOfficialUses.isNotEmpty) ...[
          const SizedBox(height: 12),
          SeniorCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 6,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                title: Text(
                  easyMode ? '더 자세한 사용 목적 보기' : '전체 허가 목적',
                  style: AppText.cardTitle(size: 22),
                ),
                children: [
                  for (final purpose in extraOfficialUses) ...[
                    _OfficialPurposeText(purpose: purpose),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 치료 쓰임 한 줄. 제목은 굵게, 설명은 그 뒤에 이어 붙인다.
class _UseLine extends StatelessWidget {
  final TreatmentUse use;

  const _UseLine({required this.use});

  @override
  Widget build(BuildContext context) {
    final base = AppText.body(size: 20);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '· ${use.title}',
            style: base.copyWith(
              color: AppColors.detailEmphasis,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (use.description.trim().isNotEmpty)
            TextSpan(text: ' ${use.description.trim()}', style: base),
        ],
      ),
      style: base,
    );
  }
}

/// 복용 방법 — 내가 받은 처방대로. 그 아래에 제품 공식 용법을 접어 둔다.
class _DoseWayCard extends StatelessWidget {
  final UserMedicine medicine;
  final bool easyMode;

  const _DoseWayCard({required this.medicine, required this.easyMode});

  @override
  Widget build(BuildContext context) {
    final eating = medicine.useType == MedicineUseType.eat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeniorCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTitle(
                icon: TablerIcons.clock,
                text: eating ? '복용 방법' : '사용 방법',
                style: AppText.cardTitle(size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                '한 번에 ${medicine.dosageLabel}, ${medicine.frequencyLabel}',
                style: AppText.body(size: 21),
              ),
              if (medicine.administrationTimes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  medicine.administrationTimes.join(' · '),
                  style: AppText.body(size: 20, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (medicine.officialUsage.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          SeniorCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 6,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                title: Text(
                  easyMode ? '공식 복용 안내 보기' : '제품 공식 용법·용량',
                  style: AppText.cardTitle(size: 22),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      medicine.officialUsageNotice.trim().isNotEmpty
                          ? medicine.officialUsageNotice
                          : '제품 설명서의 일반적인 사용법이에요. 실제로는 처방전과 의료진의 안내대로 복용하세요.',
                      style: AppText.caption(
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatOfficialUsage(medicine.officialUsage),
                      style: AppText.body(size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 주의 탭 — 꼭 기억할 것, 함께먹기, 의료진에게 알릴 때.
class _CautionTab extends StatelessWidget {
  final UserMedicine medicine;
  final List<String> cautions;

  const _CautionTab({required this.medicine, required this.cautions});

  @override
  Widget build(BuildContext context) {
    final hasConflict =
        medicine.interactionStatus == 'risk_found' &&
        (medicine.interactionSummary ?? '').trim().isNotEmpty;
    final empty =
        cautions.isEmpty && !hasConflict && medicine.askDoctorWhen.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cautions.isNotEmpty)
          SeniorCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTitle(
                  icon: TablerIcons.alert_triangle,
                  color: AppColors.danger,
                  text: '꼭 기억해 주세요',
                  style: AppText.cardTitle(size: 22, color: AppColors.danger),
                ),
                const SizedBox(height: 12),
                for (final caution in cautions) ...[
                  Text(
                    '· $caution',
                    style: AppText.body(size: 20, color: AppColors.textBody),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        if (hasConflict) ...[
          if (cautions.isNotEmpty) const SizedBox(height: 12),
          SeniorCard(
            padding: const EdgeInsets.all(22),
            borderColor: AppColors.danger,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTitle(
                  icon: TablerIcons.alert_triangle,
                  color: AppColors.danger,
                  text: '함께먹기 주의가 있어요',
                  style: AppText.cardTitle(size: 22, color: AppColors.danger),
                ),
                const SizedBox(height: 10),
                if (medicine.interactionPairLabel.trim().isNotEmpty) ...[
                  Text(
                    medicine.interactionPairLabel,
                    style: AppText.body(size: 20),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  medicine.interactionSummary!,
                  style: AppText.body(size: 20),
                ),
                if (medicine.interactionRiskFactor.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '성분 위험요소: ${medicine.interactionRiskFactor}',
                    style: AppText.label(size: 19),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '약국이나 병원에 한 번 확인해 주세요.',
                  style: AppText.label(size: 19, color: AppColors.danger),
                ),
              ],
            ),
          ),
        ],
        if (medicine.askDoctorWhen.isNotEmpty) ...[
          if (cautions.isNotEmpty || hasConflict) const SizedBox(height: 12),
          SeniorCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTitle(
                  icon: Icons.contact_support_outlined,
                  text: '언제 의료진에게 알려야 하나요?',
                  style: AppText.cardTitle(size: 22),
                ),
                const SizedBox(height: 12),
                for (final situation in medicine.askDoctorWhen) ...[
                  Text('· $situation', style: AppText.body(size: 20)),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
        // 빈 탭을 그대로 두면 안 불러온 것인지 없는 것인지 모른다.
        if (empty)
          SeniorCard(
            padding: const EdgeInsets.all(22),
            child: Text(
              '이 약에 따로 적힌 주의사항이 없어요.',
              style: AppText.body(size: 20, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _EmphasizedBodyText extends StatelessWidget {
  final String text;
  final String highlight;
  final String ingredient;
  final String fallbackHighlight;

  const _EmphasizedBodyText({
    required this.text,
    required this.highlight,
    required this.ingredient,
    required this.fallbackHighlight,
  });

  @override
  Widget build(BuildContext context) {
    final bodyStyle = AppText.body(size: 20);
    final effect = _effectTarget();
    final ranges = <_EmphasisRange>[];
    final ingredientTarget = ingredient.trim();
    final ingredientStart = ingredientTarget.isEmpty
        ? -1
        : text.indexOf(ingredientTarget);
    if (ingredientStart >= 0) {
      ranges.add(
        _EmphasisRange(
          ingredientStart,
          ingredientStart + ingredientTarget.length,
          bodyStyle.copyWith(fontWeight: FontWeight.w800),
        ),
      );
    }
    final effectStart = effect.isEmpty ? -1 : text.indexOf(effect);
    if (effectStart >= 0) {
      ranges.add(
        _EmphasisRange(
          effectStart,
          effectStart + effect.length,
          bodyStyle.copyWith(
            color: AppColors.detailEmphasis,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    if (ranges.isEmpty) {
      return Text(text, style: bodyStyle);
    }
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (range.start < cursor) continue;
      if (range.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, range.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: range.style,
        ),
      );
      cursor = range.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(TextSpan(style: bodyStyle, children: spans));
  }

  /// 본문 전체를 강조하면 강조가 아니다. 그런 값은 버린다.
  bool _wholeBody(String value) => value.trim() == text.trim();

  String _effectTarget() {
    final reviewed = highlight.trim();
    if (reviewed.isNotEmpty &&
        !_wholeBody(reviewed) &&
        text.contains(reviewed)) {
      return reviewed;
    }
    var fallback = fallbackHighlight.trim();
    if (fallback.startsWith('이 약은 ')) fallback = fallback.substring(5);
    fallback = fallback.replaceFirst(
      RegExp(r'\s*(사용해요|사용돼요|사용될 수 있어요|도움을 줘요)\.?$'),
      '',
    );
    return fallback.isNotEmpty &&
            !_wholeBody(fallback) &&
            text.contains(fallback)
        ? fallback
        : '';
  }
}

class _EmphasisRange {
  final int start;
  final int end;
  final TextStyle style;

  const _EmphasisRange(this.start, this.end, this.style);
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.pointTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: AppText.label(size: 18, color: AppColors.point),
      ),
    );
  }
}
