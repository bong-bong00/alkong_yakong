import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../domain/ingredient_explanation_display.dart';
import '../../domain/explanation_highlight.dart';
import '../../domain/official_usage_display.dart';
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
          _Profile(medicine: medicine, name: medicine.displayName),
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
              1 => _CautionTab(medicine: medicine, cautions: _cautions),
              // 무슨 약인지 읽고 나면 다음에 궁금한 것이 어떻게 먹느냐다.
              // 한 탭에 이어서 둔다.
              _ => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WorkTab(medicine: medicine),
                  const SizedBox(height: 16),
                  const SeniorDivider(),
                  const SizedBox(height: 16),
                  _DosingTab(medicine: medicine),
                ],
              ),
            },
          ),
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

  /// 물어보러 갈 때 들고 갈 약 이름.
  final String name;

  const _Profile({required this.medicine, required this.name});

  @override
  Widget build(BuildContext context) {
    final purpose = shortPurposeLabel(medicine.purposeLabel);
    final look = medicine.appearanceLine.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(width: 10),
        // 글 묶음 바깥에 둔다. 안에 두면 설명이 길어질 때 단추 밑으로
        // 글이 들어가 겹친다. 윗줄은 약 이름과 맞춘다.
        _AskAboutThisDrug(name: name),
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

  static const _labels = ['약 소개', '주의'];

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
    // 팀원이 더한 다듬기 — "이 약의 주성분으로," 뒤의 군더더기를 걷는다.
    return ingredientExplanationDisplay(
      medicine.ingredientExplanation,
      medicine.ingredientHighlight,
    );
  }

  /// 이 약이 쓰이는 경우. 한 줄에 문장을 적고, 그 안에서 짚을 낱말만
  /// 파랗게 한다. 낱말만 따로 한 줄 세우면 같은 말이 두 줄이 된다.
  List<(String, String)> get _uses {
    final seen = <String>{};
    final uses = <(String, String)>[];
    final spoken = _explanation;
    for (final use in medicine.treatmentUses) {
      final title = use.title.trim();
      final rest = use.description.trim();
      if (title.isEmpty && rest.isEmpty) continue;
      // 설명 문장이 있으면 그 문장을 적는다. 낱말은 그 문장 안에서 짚는다.
      // 조사나 가운뎃점으로 이어지면 한 말의 뒷토막이니 앞말에 붙인다.
      final phrase = rest.isEmpty
          ? title
          : _isTail(rest)
          ? '$title$rest'
          : rest;
      if (!seen.add(phrase)) continue;
      // 윗 문단이 이미 같은 말을 했으면 두 번 적지 않는다.
      if (_samePhrase(phrase, spoken)) continue;
      final mark = use.highlight.trim();
      uses.add((phrase, mark.isEmpty ? title : mark));
    }
    for (final approved in medicine.approvedUses) {
      final text = approved.trim();
      if (text.isEmpty || !seen.add(text)) continue;
      if (_samePhrase(text, spoken)) continue;
      uses.add((text, ''));
    }
    if (uses.isEmpty &&
        medicine.approvedUseSummary.trim().isNotEmpty &&
        !_samePhrase(medicine.approvedUseSummary, spoken)) {
      uses.add((medicine.approvedUseSummary.trim(), ''));
    }
    return uses;
  }

  /// 약이 아니라 자료를 설명하는 말인지.
  static bool _isNotice(String text) {
    const marks = ['허가정보', '설명서', '출처', '참고하', '확인해 주세요', '안내예요'];
    return marks.any(text.contains);
  }

  /// 두 말이 사실상 같은 말인지. 띄어쓰기·문장부호만 다른 경우가 많다.
  static bool _samePhrase(String a, String b) {
    final left = _bare(a);
    final right = _bare(b);
    if (left.isEmpty || right.isEmpty) return false;
    return left == right || right.contains(left);
  }

  /// 견주기 위해 띄어쓰기와 문장부호를 턴다.
  static String _bare(String text) =>
      text.replaceAll(RegExp(r'[\s.,·()\[\]"’“”]'), '');

  /// 앞말에 바로 붙는 뒷토막인지.
  static bool _isTail(String rest) {
    if (rest.isEmpty) return false;
    const glue = ['·', '이', '가', '은', '는', '을', '를', '과', '와', ','];
    return glue.contains(rest[0]);
  }

  /// 허가 목적 한 줄. 아래 쓰이는 경우 줄에 이미 있으면 적지 않는다.
  String get _summary {
    final summary = medicine.approvedUseSummary.trim();
    if (summary.isEmpty) return '';
    // "공식 허가정보에서 확인한 대표 사용 목적이에요" 같은 말은 약이
    // 아니라 자료를 설명한다. 출처는 맨 밑에 이미 한 줄 적혀 있다.
    if (_isNotice(summary)) return '';
    // 윗 문단이 이미 같은 말을 했으면 두 번 적지 않는다.
    if (_samePhrase(summary, _explanation)) return '';
    final shown = _uses.any((use) => use.$1 == summary);
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
            purposeHighlights: [
              for (final use in medicine.treatmentUses) ...[
                use.highlight,
                use.title,
              ],
            ],
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
          // 아래 "얼마나·언제"와 같은 틀로 읽힌다. 첫 줄에만 딱지를 단다.
          _Bullet(
            tag: i == 0 ? '쓰임' : '',
            text: uses[i].$1,
            highlight: uses[i].$2,
          ),
        ],
      ],
    );
  }
}

/// "· 앞말 + 나머지" 한 줄. 앞말만 파랗게 굵게 둔다.
class _Bullet extends StatelessWidget {
  /// 왼쪽 딱지. 비워 두면 자리만 차지해 다음 줄이 같은 줄에 선다.
  final String tag;

  /// 한 줄로 읽힐 말.
  final String text;

  /// 그 안에서 파랑게 짚을 낱말. 제목이 아니라 눈에 떨어져야 할 말이다.
  final String highlight;

  const _Bullet({this.tag = '', required this.text, this.highlight = ''});

  /// 짚을 낱말들. 통째로 들어 있으면 그대로, 아니면 가운뎃점·쉼표로
  /// 갈라 문장 안에 실제로 있는 토막만 남긴다.
  List<String> get _marks {
    final mark = highlight.trim();
    if (mark.isEmpty) return const [];
    if (text.contains(mark)) return [mark];
    return mark
        .split(RegExp(r'[·,/\s]+'))
        .map((piece) => piece.trim())
        .where((piece) => piece.length >= 2 && text.contains(piece))
        .toList();
  }

  /// 낱말마다 파랗게 끊어 둔 조각들. 짚을 것이 없으면 null.
  List<InlineSpan>? _spans(String text, TextStyle body, TextStyle strong) {
    final marks = _marks;
    if (marks.isEmpty) return null;
    final spans = <InlineSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      var at = -1;
      var hit = '';
      for (final mark in marks) {
        final found = text.indexOf(mark, cursor);
        if (found < 0) continue;
        if (at < 0 || found < at || (found == at && mark.length > hit.length)) {
          at = found;
          hit = mark;
        }
      }
      if (at < 0) break;
      if (at > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, at), style: body));
      }
      spans.add(TextSpan(text: hit, style: strong));
      cursor = at + hit.length;
    }
    if (spans.isEmpty) return null;
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: body));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final body = AppText.body(size: 19);
    final strong = AppText.cardTitle(
      size: 19,
      color: AppColors.point,
    ).copyWith(fontWeight: FontWeight.w800);

    final spans = _spans(text, body, strong);
    final line = spans == null
        ? Text(text, style: body)
        : Text.rich(TextSpan(children: spans), style: body);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 68,
          child: Text(
            tag,
            style: AppText.label(size: 18, color: AppColors.textTertiary),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: line),
      ],
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

  String get _doseLine =>
      medicine.amount.trim().isEmpty &&
          (medicine.dosage?.trim().isEmpty ?? true)
      ? ''
      : '한 번에 ${medicine.dosageLabel}';

  List<String> get _confirmedDosing => [
    if (_doseLine.isNotEmpty) _doseLine,
    if ((medicine.frequencyPerDay ?? 0) > 0) medicine.frequencyLabel,
  ];

  /// "아침, 점심, 저녁 하루 3번 드세요." 처럼 한 문장으로 잇는다.
  ///
  /// 시각을 분 단위로 적지 않는다. 08:00에 드시든 08:40에 드시든 아침
  /// 약이다. 몇 시에 울릴지는 알림이 따로 맡는다.
  String get _whenLine {
    final slots = <String>[];
    for (final time in medicine.administrationTimes) {
      final slot = _slotName(time);
      if (slot.isNotEmpty && !slots.contains(slot)) slots.add(slot);
    }
    final how = medicine.frequencyLabel.trim();
    if (slots.isEmpty) return how.isEmpty ? '처방전대로 드세요.' : '$how 드세요.';
    return '${slots.join(', ')} ${how.isEmpty ? '' : '$how '}드세요.';
  }

  /// "08:00" → "아침". 읽을 수 없는 값이면 빈 말이다.
  static String _slotName(String raw) {
    final match = RegExp(r'^(\d{1,2})\s*[:시]').firstMatch(raw.trim());
    if (match == null) return '';
    final hour = int.tryParse(match.group(1)!) ?? -1;
    if (hour < 0 || hour > 24) return '';
    if (hour < 5) return '밤';
    if (hour < 11) return '아침';
    if (hour < 17) return '점심';
    if (hour < 22) return '저녁';
    return '밤';
  }

  @override
  Widget build(BuildContext context) {
    // 꼬리말("제품 설명서의 일반적인 사용법이에요…")이 아니라 용법 문장을
    // 적는다. 머리말을 걷고, 항마다 줄을 나누고, 고령자·성인·소아 차례로
    // 세운다(팀원이 만든 formatOfficialUsage·orderOfficialUsageSections).
    final usage = orderOfficialUsageSections(
      formatOfficialUsage(officialUsageLine(medicine.officialUsage)),
    );
    // ingredientLabel 에 용량이 이미 들어 있다. 또 붙이면 "100mg · 100mg".
    final label = medicine.ingredientLabel.trim();
    final strength = medicine.ingredientStrength.trim();
    // 제조사는 성분이 아니다. 회사 이름은 적지 않는다.
    final ingredient = [
      label,
      if (strength.isNotEmpty && !label.contains(strength)) strength,
    ].where((value) => value.isNotEmpty).join(' · ');
    final rows = <(String, String)>[
      if (_confirmedDosing.isNotEmpty) ('얼마나', _confirmedDosing.join(' · ')),
      ('언제', _whenLine),
      if (usage.isNotEmpty) ('복용법', usage),
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
                // 설명서에서 그대로 온 용법은 열 줄을 넘기도 한다.
                // 다 펴 두면 아래 줄이 화면 밖으로 밀린다.
                child: _RowValue(
                  text: rows[i].$2,
                  foldable: rows[i].$1 == '복용법',
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
          // 흰 칸 두 줄. 무엇으로 묻는지("이 약으로")를 같이 적는다.
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: kCardShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '이 약으로',
                  style: AppText.caption(
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text('챗봇 상담', style: AppText.cardTitle(size: 16)),
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
  final List<String> purposeHighlights;

  const _EmphasizedBodyText({
    required this.text,
    required this.highlight,
    required this.ingredient,
    required this.fallbackHighlight,
    required this.purposeHighlights,
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

  String _effectTarget() {
    var fallback = fallbackHighlight.trim();
    if (fallback.startsWith('이 약은 ')) fallback = fallback.substring(5);
    fallback = fallback.replaceFirst(
      RegExp(r'\s*(사용해요|사용돼요|사용될 수 있어요|도움을 줘요)\.?$'),
      '',
    );
    return explanationHighlight(text, [
      highlight,
      fallback,
      ...purposeHighlights,
    ]);
  }
}

class _EmphasisRange {
  final int start;
  final int end;
  final TextStyle style;

  const _EmphasisRange(this.start, this.end, this.style);
}

/// 줄 하나의 값. 긴 말은 세 줄만 보이고 "더 보기"로 편다.
class _RowValue extends StatefulWidget {
  final String text;

  /// 접을 수 있는 줄인지. 짧은 줄은 접을 까닭이 없다.
  final bool foldable;

  const _RowValue({required this.text, this.foldable = false});

  @override
  State<_RowValue> createState() => _RowValueState();
}

class _RowValueState extends State<_RowValue> {
  bool _open = false;

  /// 세 줄 안에 들어가는 길이면 접지 않는다.
  bool get _long => widget.foldable && widget.text.length > 70;

  @override
  Widget build(BuildContext context) {
    final style = AppText.cardTitle(size: 19).copyWith(height: 1.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          style: style,
          maxLines: _long && !_open ? 3 : null,
          overflow: _long && !_open ? TextOverflow.ellipsis : null,
        ),
        if (_long) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            behavior: HitTestBehavior.opaque,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.centerLeft,
              child: Text(
                _open ? '접기' : '더 보기',
                style: AppText.cardTitle(size: 18, color: AppColors.point),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
