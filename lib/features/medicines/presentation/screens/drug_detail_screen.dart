import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/medicine_flow_colors.dart';
import '../../../../core/mode/app_mode.dart';
import '../../../../core/theme/medicine_flow_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/medicine_flow_card.dart' hide PillPhoto;
import '../../../../core/widgets/senior_card.dart' show PillPhoto, kCardShadow;
import '../../../../core/widgets/senior_header.dart';
import '../../application/user_medicines_controller.dart';
import '../../domain/display_policy.dart';
import '../../domain/user_medicine_models.dart';

/// 내 약 한 종류 상세 — 서버 쉬운말·주의·복용 정보.
///
/// 받은 화면 그대로: 위에 약의 얼굴(사진·이름·무슨 약·생김새), 그 아래
/// **하는 일 · 주의 · 먹는 법** 세 탭, 탭마다 카드 한 장, 맨 아래에
/// 물어보는 단추와 출처 한 줄.
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
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final UserMedicine medicine;
  final bool easyMode;
  final int tab;
  final ValueChanged<int> onTabChanged;

  const _DetailBody({
    required this.medicine,
    required this.easyMode,
    required this.tab,
    required this.onTabChanged,
  });

  /// 사람에게 해당하는 주의만 골라 세 개까지.
  List<String> get _cautions => <String>[
    if ((medicine.keyCaution ?? '').trim().isNotEmpty) medicine.keyCaution!,
    ...medicine.keyCautions.where(
      (c) => c.trim().isNotEmpty && c != medicine.keyCaution,
    ),
  ].where(_isPersonCaution).take(3).toList();

  bool get _hasConflict =>
      medicine.interactionStatus == 'risk_found' &&
      (medicine.interactionSummary ?? '').trim().isNotEmpty;

  /// 주의 탭에 붉은 점을 붙일지. 볼 것이 있을 때만 붙인다.
  bool get _hasCaution =>
      _hasConflict || _cautions.isNotEmpty || medicine.askDoctorWhen.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Profile(medicine: medicine),
          const SizedBox(height: 16),
          _DetailTabs(
            index: tab,
            onChanged: onTabChanged,
            cautionMark: _hasCaution,
          ),
          const SizedBox(height: 14),
          SeniorCard(
            radius: 26,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: switch (tab) {
              0 => _WorkTab(medicine: medicine),
              1 => _CautionTab(medicine: medicine, cautions: _cautions),
              _ => _DosingTab(medicine: medicine),
            },
          ),
          const SizedBox(height: 14),
          // 읽다가 모르는 것이 생기면 그 자리에서 물어보게 한다. 약 이름을
          // 다시 고르게 하지 않는다 — 지금 보고 있는 약이 곧 그 약이다.
          _AskAboutThisDrug(name: medicine.displayName),
          // 출처는 박스에 담지 않는다. 읽을 거리가 아니라 꼬리말이다.
          if (medicine.detailSourceName.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '정보 출처 · 식약처 의약품 허가정보',
              style: AppText.caption(size: 16, color: AppColors.textTertiary),
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

/// 약의 얼굴 — 사진, 이름, 무슨 약인지 한 줄, 생김새.
///
/// 이름에는 용량을 적지 않는다. 용량은 "먹는 법"의 성분 줄에 한 번만 적는다.
class _Profile extends StatelessWidget {
  final UserMedicine medicine;

  const _Profile({required this.medicine});

  @override
  Widget build(BuildContext context) {
    final purpose = (medicine.purposeLabel ?? '').trim();
    final look = medicine.appearanceLine.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PillPhoto(size: 72, imageUrl: medicine.imageUrl),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nameWithoutStrength(
                  medicine.displayName,
                  strength: medicine.ingredientStrength,
                ),
                style: AppText.screenTitle(size: 25),
              ),
              if (purpose.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  purpose,
                  style: AppText.cardTitle(size: 19, color: AppColors.point),
                ),
              ],
              if (look.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  look,
                  style: AppText.body(size: 17, color: AppColors.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 하는 일 · 주의 · 먹는 법. 한 번에 한 묶음만 보여 준다.
///
/// 주의할 것이 있으면 "주의" 앞에 붉은 점을 찍는다.
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
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _labels[i],
                                maxLines: 1,
                                style: AppText.cardTitle(
                                  size: 19,
                                  color: i == index
                                      ? Colors.white
                                      : AppColors.textBody,
                                ),
                              ),
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

/// 하는 일 — 설명 한 단락, 선, 쓰이는 경우 줄.
class _WorkTab extends StatelessWidget {
  final UserMedicine medicine;

  const _WorkTab({required this.medicine});

  /// 이 약이 무슨 일을 하는지 한 문장. 검토된 쉬운말을 먼저 쓰고,
  /// 없으면 성분 설명을 쓴다. 두 가지를 같이 적지 않는다.
  String get _explanation {
    final spoken = medicine.detailSpoken ?? '';
    if (spoken.trim().isNotEmpty) return spoken;
    return medicine.ingredientExplanation;
  }

  /// 이 약이 쓰이는 경우. 앞말(병 이름)만 파랗게 짚는다.
  List<(String?, String)> get _uses {
    final seen = <String>{};
    final uses = <(String?, String)>[];
    for (final use in medicine.treatmentUses) {
      final title = use.title.trim();
      if (title.isEmpty || !seen.add(title)) continue;
      uses.add((title, use.description.trim()));
    }
    for (final approved in medicine.approvedUses) {
      final text = approved.trim();
      if (text.isEmpty || !seen.add(text)) continue;
      uses.add((null, text));
    }
    if (uses.isEmpty && medicine.approvedUseSummary.trim().isNotEmpty) {
      uses.add((null, medicine.approvedUseSummary.trim()));
    }
    return uses;
  }

  /// 허가 목적 한 줄. 아래 쓰이는 경우 줄에 이미 있으면 적지 않는다.
  String get _summary {
    final summary = medicine.approvedUseSummary.trim();
    if (summary.isEmpty) return '';
    final shown = _uses.any((use) => use.$2 == summary || use.$1 == summary);
    return shown ? '' : summary;
  }

  @override
  Widget build(BuildContext context) {
    final explanation = _explanation;
    final uses = _uses;
    if (explanation.trim().isEmpty && uses.isEmpty) {
      return Text(
        _detailStatusMessage(medicine.detailStatus),
        style: AppText.body(size: 19),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (explanation.trim().isNotEmpty)
          _EmphasizedBodyText(
            text: explanation,
            highlight: medicine.ingredientHighlight,
            ingredient: medicine.ingredientName,
            fallbackHighlight: medicine.approvedUseSummary,
          ),
        if (_summary.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_summary, style: AppText.body(size: 19)),
        ],
        if (explanation.trim().isNotEmpty && uses.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SeniorDivider(),
          const SizedBox(height: 14),
        ],
        for (int i = 0; i < uses.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _Bullet(emphasis: uses[i].$1, rest: uses[i].$2),
        ],
      ],
    );
  }
}

/// "· 앞말 + 나머지" 한 줄. 앞말만 파랗게 굵게 둔다.
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
      color: AppColors.point,
    ).copyWith(fontWeight: FontWeight.w800);
    final head = emphasis?.trim() ?? '';

    // 한 줄로 흐르게 둔다. 가운뎃점을 따로 떼면 "혈전이 생기기 쉬운 / 분"
    // 처럼 끊겨 읽힌다.
    if (head.isEmpty) return Text('· $rest', style: body);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '· $head', style: strong),
          if (rest.isNotEmpty) TextSpan(text: _join(rest), style: body),
        ],
      ),
      style: body,
    );
  }
}

/// 주의 — 함께 먹으면 안 되는 약, 꼭 기억할 것, 의료진에게 알릴 때.
///
/// 약 이름과 몸에 나타나는 신호만 붉게 짚는다. 문단을 통째로 붉게 하면
/// 어디를 봐야 할지 알 수 없다.
class _CautionTab extends StatelessWidget {
  final UserMedicine medicine;
  final List<String> cautions;

  const _CautionTab({required this.medicine, required this.cautions});

  bool get _hasConflict =>
      medicine.interactionStatus == 'risk_found' &&
      (medicine.interactionSummary ?? '').trim().isNotEmpty;

  /// 몸에 나타나는 신호 — 이것만 붉게 짚는다.
  List<String> get _marks => [
    if (medicine.interactionRiskFactor.trim().isNotEmpty)
      medicine.interactionRiskFactor.trim(),
    '피가 잘 멈추지 않을 수 있어요',
    '피가 잘 멈추지 않으면',
    '검은색 변',
    '코피·잇몸 피',
    '코피',
    '잇몸 피',
    '출혈',
    '어지러움',
    '숨이 차',
  ];

  @override
  Widget build(BuildContext context) {
    final interaction = (medicine.interactionSummary ?? '').trim();
    final others = medicine.interactionConflictNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    if (!_hasConflict && cautions.isEmpty && medicine.askDoctorWhen.isEmpty) {
      return Text('이 약에 따로 적힌 주의사항이 없어요.', style: AppText.body(size: 19));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasConflict) ...[
          if (others.isNotEmpty)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: others.first,
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
          _Marked(text: interaction, marks: _marks),
        ],
        for (final caution in cautions) ...[
          const SizedBox(height: 12),
          _Marked(text: caution, marks: _marks),
        ],
        for (final ask in medicine.askDoctorWhen) ...[
          const SizedBox(height: 12),
          _Marked(text: ask, marks: _marks),
        ],
      ],
    );
  }
}

/// 글 한 단락. [marks]에 든 말만 붉게 굵게 짚는다.
class _Marked extends StatelessWidget {
  final String text;
  final List<String> marks;

  const _Marked({required this.text, required this.marks});

  @override
  Widget build(BuildContext context) {
    final base = AppText.body(size: 19);
    final strong = base.copyWith(
      color: AppColors.danger,
      fontWeight: FontWeight.w800,
    );

    final spans = <TextSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      // 가장 앞에서 걸리는 말을 찾는다. 같은 자리면 긴 쪽을 짚는다.
      var at = -1;
      var hit = '';
      for (final mark in marks) {
        if (mark.isEmpty) continue;
        final found = rest.indexOf(mark);
        if (found < 0) continue;
        if (at < 0 || found < at || (found == at && mark.length > hit.length)) {
          at = found;
          hit = mark;
        }
      }
      if (at < 0) {
        spans.add(TextSpan(text: rest, style: base));
        break;
      }
      if (at > 0) spans.add(TextSpan(text: rest.substring(0, at), style: base));
      spans.add(TextSpan(text: hit, style: strong));
      rest = rest.substring(at + hit.length);
    }

    return Text.rich(TextSpan(children: spans), style: base);
  }
}

/// 먹는 법 — 얼마나 · 언제 · 식사 · 성분을 이름과 값으로 둔다.
class _DosingTab extends StatelessWidget {
  final UserMedicine medicine;

  const _DosingTab({required this.medicine});

  /// "아침 8시에 하루 한 번 드세요." 처럼 한 문장으로 잇는다.
  String get _whenLine {
    final times = medicine.administrationTimes
        .map((time) => time.trim())
        .where((time) => time.isNotEmpty)
        .toList();
    final how = medicine.frequencyLabel.trim();
    if (times.isEmpty) return how.isEmpty ? '처방전대로 드세요.' : '$how 드세요.';
    return '${times.join(' · ')}에 ${how.isEmpty ? '' : '$how '}드세요.';
  }

  @override
  Widget build(BuildContext context) {
    final eating = medicine.useType == MedicineUseType.eat;
    final ingredient = [
      medicine.ingredientLabel.trim(),
      medicine.ingredientStrength.trim(),
      medicine.manufacturer.trim(),
    ].where((value) => value.isNotEmpty).join(' · ');
    final meal = medicine.officialUsageNotice.trim();

    final rows = <(String, String)>[
      ('얼마나', '한 번에 ${medicine.dosageLabel} · ${medicine.frequencyLabel}'),
      ('언제', _whenLine),
      if (meal.isNotEmpty) (eating ? '식사' : '쓰는 법', meal),
      if (ingredient.isNotEmpty) ('성분', ingredient),
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
                width: 68,
                child: Text(
                  rows[i].$1,
                  style: AppText.label(size: 18, color: AppColors.textTertiary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rows[i].$2,
                  style: AppText.cardTitle(size: 19).copyWith(height: 1.45),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// "이 약, AI 약사에게 묻기" — 지금 보고 있는 약을 고른 채로 연다.
class _AskAboutThisDrug extends StatelessWidget {
  final String name;

  const _AskAboutThisDrug({required this.name});

  @override
  Widget build(BuildContext context) {
    final short = nameWithoutStrength(name);
    return Semantics(
      button: true,
      label: '$short 물어보기',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => context.push('/drug-explain', extra: name),
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: kCardShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  TablerIcons.help_circle,
                  size: 26,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '이 약, AI 약사에게 묻기',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardTitle(size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
            color: AppColors.point,
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
