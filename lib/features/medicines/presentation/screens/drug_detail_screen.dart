import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
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

  /// 지금 보고 있는 탭. 0 하는 일 · 1 주의 · 2 먹는 법.
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
      backgroundColor: AppColors.pageBg,
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
                    onTabChanged: (i) => setState(() => _tab = i),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final UserMedicine medicine;
  final bool easyMode;

  /// 0 하는 일 · 1 주의 · 2 먹는 법.
  final int tab;
  final ValueChanged<int> onTabChanged;

  const _DetailBody({
    required this.medicine,
    required this.easyMode,
    required this.tab,
    required this.onTabChanged,
  });

  /// 머리에 적는 설명 한 단락.
  /// 적힌 그대로 둔다 — 앞뒤 빈칸까지 서버 글을 그대로 보여 준다.
  String get _explanation =>
      medicine.detailSpoken ?? medicine.ingredientExplanation;

  /// 이름에서 용량을 뗀다 — 바로 밑 주성분 줄에 또 적히기 때문이다.
  /// "아스피린 100mg" → "아스피린".
  static String _nameWithoutStrength(UserMedicine medicine) {
    final name = medicine.displayName.trim();
    final strength = medicine.ingredientStrength.trim();
    if (strength.isNotEmpty &&
        name.toLowerCase().endsWith(strength.toLowerCase())) {
      final cut = name.substring(0, name.length - strength.length).trim();
      if (cut.isNotEmpty) return cut;
    }
    final cut = name
        .replaceFirst(
          RegExp(
            r'[\s·]*\d+(\.\d+)?\s*(mg|밀리그램|mcg|㎍|g|ml|㎖|iu|%)\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    return cut.isEmpty ? name : cut;
  }

  /// 사람에게 해당하는 주의만 골라 세 개까지.
  List<String> get _cautions => <String>[
    if ((medicine.keyCaution ?? '').trim().isNotEmpty) medicine.keyCaution!,
    ...medicine.keyCautions.where(
      (c) => c.trim().isNotEmpty && c != medicine.keyCaution,
    ),
  ].where(_isPersonCaution).take(3).toList();

  bool get _hasInteraction =>
      medicine.interactionStatus == 'risk_found' &&
      (medicine.interactionSummary ?? '').trim().isNotEmpty;

  /// 주의 탭에 붉은 점을 붙일지. 볼 것이 있을 때만 붙인다.
  bool get _hasCaution =>
      _hasInteraction ||
      _cautions.isNotEmpty ||
      medicine.askDoctorWhen.isNotEmpty;

  /// 이 약이 쓰이는 경우. 앞말(병 이름)만 파랗게 짚는다.
  List<_Use> get _uses {
    final seen = <String>{};
    final uses = <_Use>[];
    for (final use in medicine.treatmentUses) {
      final title = use.title.trim();
      if (title.isEmpty || !seen.add(title)) continue;
      uses.add(_Use(emphasis: title, rest: use.description.trim()));
    }
    for (final approved in medicine.approvedUses) {
      final text = approved.trim();
      if (text.isEmpty || !seen.add(text)) continue;
      uses.add(_Use(rest: text));
    }
    if (uses.isEmpty && medicine.approvedUseSummary.trim().isNotEmpty) {
      uses.add(_Use(rest: medicine.approvedUseSummary.trim()));
    }
    return uses;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 사진 오른쪽에 이름을 쌓는다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PillPhoto(size: 84, imageUrl: medicine.imageUrl),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _nameWithoutStrength(medicine),
                      style: AppText.screenTitle(size: 26),
                    ),
                    if ((medicine.purposeLabel ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        medicine.purposeLabel!,
                        style: AppText.cardTitle(
                          size: 19,
                          color: AppColors.point,
                        ),
                      ),
                    ],
                    if (medicine.appearanceLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        medicine.appearanceLine,
                        style: AppText.body(size: 17),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_explanation.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _HighlightText(
              text: _explanation,
              highlight: medicine.ingredientHighlight,
            ),
          ],
          const SizedBox(height: 14),
          // 묻는 길은 프로필 옆에 하나만 둔다 — 탭마다 따라다니지 않는다.
          SeniorButton(
            label: '이 약, AI 약사에게 묻기',
            icon: TablerIcons.help_circle,
            kind: SeniorButtonKind.card,
            minHeight: 64,
            radius: 18,
            fontSize: 20,
            onPressed: () => context.push('/drug-explain'),
          ),
          const SizedBox(height: 16),
          _DetailTabs(
            index: tab,
            onChanged: onTabChanged,
            cautionMark: _hasCaution,
          ),
          const SizedBox(height: 14),
          SeniorCard(
            radius: 26,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: switch (tab) {
              0 => _work(),
              1 => _caution(),
              _ => _dosing(),
            },
          ),
          if (medicine.detailSourceName.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '정보 출처 · 식약처 의약품 허가정보',
              style: AppText.caption(size: 16, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// 하는 일 — 이 약이 쓰이는 경우를 줄로 센다.
  ///
  /// 설명 한 단락은 머리에 이미 적혀 있다. 같은 말을 두 번 적지 않는다.
  Widget _work() {
    final uses = _uses;
    if (uses.isEmpty) {
      return Text(
        _explanation.trim().isEmpty
            ? _detailStatusMessage(medicine.detailStatus)
            : '이 약이 쓰이는 경우가 따로 적혀 있지 않아요.',
        style: AppText.body(size: 19),
      );
    }

    final summary = medicine.approvedUseSummary.trim();
    final showSummary =
        summary.isNotEmpty && !uses.any((use) => use.rest == summary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('이럴 때 씁니다', style: AppText.label(size: 19)),
        const SizedBox(height: 12),
        if (showSummary) ...[
          Text(summary, style: AppText.body(size: 19)),
          const SizedBox(height: 10),
        ],
        for (int i = 0; i < uses.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _Bullet(emphasis: uses[i].emphasis, rest: uses[i].rest),
        ],
      ],
    );
  }

  /// 주의 — 제목 한 줄과 문단. 약 이름만 붉게 짚는다.
  Widget _caution() {
    final cautions = _cautions;
    final interaction = (medicine.interactionSummary ?? '').trim();

    if (!_hasCaution) {
      return Text('이 약에 따로 적힌 주의사항이 없어요.', style: AppText.body(size: 19));
    }

    final other = medicine.interactionConflictNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasInteraction) ...[
          if (other.isNotEmpty)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: other.first,
                    style: AppText.cardTitle(size: 21, color: AppColors.danger),
                  ),
                  TextSpan(
                    text: '과 함께 드시는 건 주의해 주세요',
                    style: AppText.cardTitle(size: 21),
                  ),
                ],
              ),
            )
          else
            Text(
              medicine.interactionPairLabel.trim().isEmpty
                  ? '함께 드실 때 주의가 필요해요'
                  : medicine.interactionPairLabel,
              style: AppText.cardTitle(size: 21),
            ),
          const SizedBox(height: 12),
          Text(interaction, style: AppText.body(size: 19)),
        ],
        for (final caution in cautions) ...[
          const SizedBox(height: 12),
          Text(caution, style: AppText.body(size: 19)),
        ],
        for (final ask in medicine.askDoctorWhen) ...[
          const SizedBox(height: 12),
          Text(ask, style: AppText.body(size: 19)),
        ],
      ],
    );
  }

  /// 먹는 법 — 얼마나 · 언제 · 식사 · 성분을 이름과 값으로 둔다.
  Widget _dosing() {
    final rows = <List<String>>[
      ['얼마나', '한 번에 ${medicine.dosageLabel} · ${medicine.frequencyLabel}'],
      if (medicine.administrationTimes.isNotEmpty)
        ['언제', medicine.administrationTimes.join(' · ')],
      if (medicine.officialUsageNotice.trim().isNotEmpty)
        ['식사', medicine.officialUsageNotice.trim()],
      if (medicine.ingredientLabel.trim().isNotEmpty)
        [
          '성분',
          [
            medicine.ingredientLabel.trim(),
            medicine.manufacturer.trim(),
          ].where((value) => value.isNotEmpty).join(' · '),
        ],
      if (medicine.officialUsage.trim().isNotEmpty)
        ['공식 용법', formatOfficialUsage(medicine.officialUsage)],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 12),
            const SeniorDivider(),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  rows[i][0],
                  style: AppText.label(
                    size: 17,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  rows[i][1],
                  style: AppText.label(size: 19, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

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
      'FAILED' => '자세한 설명을 불러오지 못했어요.',
      'OUTDATED' => '최신 공식 정보로 갱신 중이에요.',
      _ => '아직 자세한 설명이 없어요.',
    };
  }
}

/// 받은 화면의 탭 — 흰 칸 안 세 칸. 고른 것만 파랗게 채운다.
/// 볼 주의가 있으면 "주의" 앞에 붉은 점을 둔다.
class _DetailTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final bool cautionMark;

  const _DetailTabs({
    required this.index,
    required this.onChanged,
    required this.cautionMark,
  });

  static const _labels = ['하는 일', '주의', '먹는 법'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: kCardShadow,
      ),
      child: Row(
        children: [
          for (int i = 0; i < _labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                label: _labels[i],
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onTap: () => onChanged(i),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == index
                            ? AppColors.point
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i == 1 && cautionMark) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.danger,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _labels[i],
                            style: AppText.cardTitle(
                              size: 19,
                              color: i == index
                                  ? Colors.white
                                  : AppColors.textBody,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 쓰이는 경우 한 줄. [emphasis]가 있으면 앞말만 초록으로 굵게 둔다.
class _Use {
  final String? emphasis;
  final String rest;

  const _Use({this.emphasis, required this.rest});
}

/// "· 앞말 + 나머지" 한 줄.
class _Bullet extends StatelessWidget {
  final String? emphasis;
  final String rest;

  const _Bullet({this.emphasis, required this.rest});

  /// 조사나 가운뎃점으로 이어지면 사이를 띄우지 않는다.
  static String _join(String rest) {
    if (rest.isEmpty) return '';
    const glue = ['·', '이', '가', '은', '는', '을', '를', '과', '와', ','];
    return glue.contains(rest[0]) ? rest : ' $rest';
  }

  @override
  Widget build(BuildContext context) {
    final body = AppText.body(size: 19);
    final strong = AppText.cardTitle(
      size: 19,
      color: AppColors.detailEmphasis,
    ).copyWith(fontWeight: FontWeight.w800);
    final head = emphasis?.trim() ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('·', style: body),
        const SizedBox(width: 8),
        Expanded(
          child: head.isEmpty
              ? Text(rest, style: body)
              : Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: head, style: strong),
                      if (rest.isNotEmpty)
                        TextSpan(text: _join(rest), style: body),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// 설명 한 단락. 서버가 짚어 준 핵심 구절만 초록으로 굵게 둔다.
///
/// 짚을 구절이 없거나, 문단 전체와 같거나, 문단에 없으면 그냥 글로 둔다 —
/// 문단을 통째로 강조하면 아무것도 강조하지 않은 것과 같다.
class _HighlightText extends StatelessWidget {
  final String text;
  final String highlight;

  const _HighlightText({required this.text, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final style = AppText.label(
      size: 20,
      color: AppColors.textPrimary,
    ).copyWith(height: 1.5);
    final target = highlight.trim();
    final start = target.isEmpty ? -1 : text.indexOf(target);
    final wholeBody = target == text.trim();

    if (start < 0 || wholeBody) return Text(text, style: style);

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: target,
            style: style.copyWith(
              color: AppColors.detailEmphasis,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: text.substring(start + target.length)),
        ],
      ),
    );
  }
}
