import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/theme/medicine_preserved_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../prescription/domain/registration_result.dart';

const _pairTypes = {'병용금기', '중복성분', '효능군중복'};

/// 4f — 약 함께먹기 주의.
///
/// 약끼리 부딪히는 빨간 카드만 보여 준다. DUR 검사표는 쓰지 않는다.
class DurAnalysisScreen extends ConsumerStatefulWidget {
  final VoidCallback? onGoHome;
  final VoidCallback? onOpenScheduleDays;
  final Map<String, dynamic>? initialResult;

  const DurAnalysisScreen({
    super.key,
    this.onGoHome,
    this.onOpenScheduleDays,
    this.initialResult,
  });

  @override
  ConsumerState<DurAnalysisScreen> createState() => _DurAnalysisScreenState();
}

class _DurAnalysisScreenState extends ConsumerState<DurAnalysisScreen> {
  final ApiClient _apiClient = ApiClient(
    baseUrl: ApiConfig.localFeatureBaseUrl,
  );
  String _guardianTitle = '보호자 가족 님';

  bool _loading = true;
  bool _failed = false;
  bool _incomplete = false;
  String _assessmentStatus = 'INCOMPLETE';
  List<Map<String, dynamic>> _matches = const [];

  @override
  void initState() {
    super.initState();
    _loadNames();
    final initialResult = widget.initialResult;
    if (initialResult == null) {
      _loadLatestOrAnalyze();
    } else {
      _applyResponse(initialResult, notify: false);
    }
  }

  Future<void> _loadLatestOrAnalyze() async {
    final userId = Uri.encodeComponent(MvpSession.userId.trim());
    try {
      final response = await _apiClient.get('/api/v1/users/$userId/dur/latest');
      if (!mounted) return;
      if (response is Map) {
        _applyResponse(Map<String, dynamic>.from(response));
        unawaited(ref.read(medicationProvider.notifier).refreshFromServer());
        return;
      }
    } catch (_) {}
    await _analyze();
  }

  Future<void> _loadNames() async {
    final today = ref.read(medicationProvider);
    final fromToday = '${today.guardianRelation} ${today.guardianName} 님'
        .trim();
    final userId = Uri.encodeComponent(MvpSession.userId);
    var guardianTitle = fromToday.isEmpty ? _guardianTitle : fromToday;
    try {
      final guardians = await _apiClient.get('/api/v1/guardians/users/$userId');
      if (guardians is List && guardians.isNotEmpty && guardians.first is Map) {
        final row = Map<String, dynamic>.from(guardians.first as Map);
        final relation = row['relationship']?.toString().trim() ?? '';
        final name = row['guardian_name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          guardianTitle = relation.isEmpty ? '$name 님' : '$relation $name 님';
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _guardianTitle = guardianTitle);
  }

  void _applyResponse(Map<String, dynamic> response, {bool notify = true}) {
    final matches = response['matches'];
    final parsedMatches = matches is List
        ? matches
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
        : <Map<String, dynamic>>[];
    final incomplete = !registrationDurComplete(response);

    void assign() {
      _matches = parsedMatches;
      _incomplete = incomplete;
      _assessmentStatus = incomplete
          ? 'INCOMPLETE'
          : response['assessment_status']?.toString() ??
                (parsedMatches.isNotEmpty ? 'RISK_FOUND' : 'SAFE');
      _loading = false;
      _failed = false;
    }

    if (notify) {
      setState(assign);
    } else {
      assign();
    }
  }

  Future<void> _analyze() async {
    setState(() {
      _loading = true;
      _failed = false;
      _incomplete = false;
    });

    final userId = MvpSession.userId.trim();
    try {
      final body = <String, dynamic>{
        'user_id': userId,
        'medicine_codes': <String>[],
      };
      if (MvpSession.isPregnant != null) {
        body['is_pregnant'] = MvpSession.isPregnant;
      }
      final response = await _apiClient.post('/api/v1/dur/analyze', body: body);
      if (!mounted) return;
      if (response is! Map) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      _applyResponse(Map<String, dynamic>.from(response));
      unawaited(ref.read(medicationProvider.notifier).refreshFromServer());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  List<Map<String, dynamic>> get _pairMatches {
    return [
      for (final match in _matches)
        if (_pairTypes.contains((match['type'] ?? '').toString())) match,
    ];
  }

  /// 명세서 29에는 꼬리말이 없다. 확인하지 못한 항목은 칸 안에서 말한다.
  String get _footerNote => '';

  /// 약 설명 줄에서 부를 이름. 부딪히는 약이 있으면 그 약을 먼저 부른다.
  String get _askName {
    for (final match in _pairMatches) {
      final medicines = _ConflictCard.pairMedicines(match);
      if (medicines.isNotEmpty) return medicines.first.name;
    }
    return '이 약';
  }

  /// 받침이 있으면 "은", 없으면 "는".
  static String _topicParticle(String word) {
    if (word.isEmpty) return '은';
    final code = word.codeUnitAt(word.length - 1);
    if (code < 0xAC00 || code > 0xD7A3) return '은';
    return (code - 0xAC00) % 28 == 0 ? '는' : '은';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '약 함께먹기 주의'),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: AppColors.point,
                ),
              ),
              const SizedBox(height: 22),
              Text('약을 하나씩 살펴보고 있어요', style: AppText.emphasis()),
            ],
          ),
        ),
      );
    }

    if (_failed) {
      return RecoveryView(
        title: '지금은 약을\n살펴보지 못하고 있어요',
        reassurance: '전화기가 인터넷에 닿지 않고 있어요. ',
        reassuranceEmphasis: '고장이 아니니 걱정하지 마세요.',
        steps: const [
          '집 안 와이파이가 켜져 있는지 보세요',
          '전화기를 껐다 다시 켜보세요',
          '잠시 뒤 아래 단추를 눌러주세요',
        ],
        actionLabel: '다시 살펴보기',
        onAction: _loadLatestOrAnalyze,
        stillWorksTitle: '약 알림은 그대로 와요',
        stillWorksBody: '인터넷이 끊겨도 복약 알림에는 영향이 없어요.',
        helperText: '그래도 안 되면\n$_guardianTitle에게 도움 청하기',
        onCallHelper: _callGuardian,
      );
    }

    final pairs = _pairMatches;
    final footer = _footerNote;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 부딪히는 약이 있으면 아래 칸이 그 자체로 말한다.
          // 없을 때만 한 줄로 알린다.
          if (pairs.isEmpty) ...[
            SeniorCard(
              radius: 26,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Text(
                _incomplete
                    ? '약은 등록됐지만 함께먹기 확인을 마치지 못했어요.'
                    : '확인한 범위에서 함께먹기 주의 항목은 없어요.',
                style: AppText.label(size: 19, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 14),
          ],
          for (final match in pairs) ...[
            _ConflictCard(match: match),
            const SizedBox(height: 12),
          ],
          if (footer.isNotEmpty) ...[
            Text(footer, style: AppText.caption()),
            const SizedBox(height: 12),
          ],
          SeniorCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            onTap: () => context.push('/drug-explain'),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_askName${_topicParticle(_askName)} 무슨 약인가요?',
                        style: AppText.cardTitle(size: 19),
                      ),
                      Text('쉬운 말로 알려드려요', style: AppText.caption()),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const SeniorChevron(),
              ],
            ),
          ),
          if (pairs.isNotEmpty || _assessmentStatus == 'RISK_FOUND') ...[
            const SizedBox(height: 16),
            SeniorButton(
              label: '확인했어요',
              minHeight: 64,
              fontSize: 22,
              onPressed: _afterConfirm,
            ),
          ],
        ],
      ),
    );
  }

  /// 회복 화면에서 "도움 청하기"를 누를 때 (명세서 58).
  void _callGuardian() {
    showSeniorSnackbar(context, '$_guardianTitle에게 알려드렸어요');
  }

  Future<void> _afterConfirm() async {
    final onOpenScheduleDays = widget.onOpenScheduleDays;
    if (onOpenScheduleDays != null) {
      onOpenScheduleDays();
      return;
    }
    if (widget.initialResult?['open_schedule_days'] == true) {
      context.push('/schedule-days', extra: MvpSession.latestPrescriptionId);
      return;
    }
    final go = await showSeniorYesNoDialog(
      context: context,
      title: '이제 홈으로 갈까요?',
      message: '같이 드실 때 조심할 약을 보셨어요.',
    );
    if (!mounted || !go) return;
    final onGoHome = widget.onGoHome;
    if (onGoHome != null) {
      onGoHome();
      return;
    }
    context.go('/');
  }
}

class _ConflictCard extends StatelessWidget {
  final Map<String, dynamic> match;

  const _ConflictCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final medicines = pairMedicines(match);
    final why = _whyEasy(match);
    final source = _sourceLabel(match);

    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      borderColor: AppColors.danger,
      borderWidth: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 시안 22 — 무엇과 무엇이 부딪히는지를 한 문장으로 먼저 말한다.
          // 배지로 "꼭 확인하세요"라고만 하면 무엇을 확인할지가 아래로 밀린다.
          if (medicines.length >= 2)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: medicines[0].name,
                    style: AppText.cardTitle(size: 22, color: AppColors.danger),
                  ),
                  TextSpan(text: '과 ', style: AppText.cardTitle(size: 22)),
                  TextSpan(
                    text: medicines[1].name,
                    style: AppText.cardTitle(size: 22, color: AppColors.danger),
                  ),
                  TextSpan(
                    text: '은 함께 드시는 건 주의해 주세요',
                    style: AppText.cardTitle(size: 22),
                  ),
                ],
              ),
            )
          else
            Text(
              '함께 드실 때 주의가 필요해요',
              style: AppText.cardTitle(size: 22, color: AppColors.danger),
            ),
          if (why.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _whyHeadline(why),
              style: AppText.label(size: 19, color: AppColors.textPrimary),
            ),
            if (_whyDetail(why).isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_whyDetail(why), style: AppText.body(size: 19)),
            ],
          ],
          if (source.isNotEmpty) ...[
            const SizedBox(height: 12),
            // 출처는 참고용이다. 본문보다 눈에 덜 띄게 둔다.
            Text(source, style: AppText.caption(size: 17)),
          ],
        ],
      ),
    );
  }

  static List<_NamedMedicine> pairMedicines(Map<String, dynamic> match) {
    final namesA = _namesOf(match['medicine_names_a']);
    final namesB = _namesOf(match['medicine_names_b']);
    final uniqueA = namesA.isEmpty ? '' : namesA.first;
    var uniqueB = namesB.isEmpty ? '' : namesB.first;
    if (uniqueB.isEmpty || uniqueB == uniqueA) {
      final all = [...namesA, ...namesB].where((n) => n.isNotEmpty).toList();
      final unique = <String>[];
      for (final name in all) {
        if (!unique.contains(name)) unique.add(name);
      }
      if (unique.length >= 2) {
        return [_NamedMedicine(unique[0]), _NamedMedicine(unique[1])];
      }
      if (unique.length == 1) {
        return [_NamedMedicine(unique[0])];
      }
      return const [];
    }
    return [_NamedMedicine(uniqueA), _NamedMedicine(uniqueB)];
  }

  static List<String> _namesOf(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final value in raw)
        if (_shortDrugName(value.toString()).isNotEmpty)
          _shortDrugName(value.toString()),
    ];
  }

  static String _shortDrugName(String name) {
    final trimmed = name.trim();
    final index = trimmed.indexOf('(');
    if (index > 0) return trimmed.substring(0, index).trim();
    return trimmed;
  }

  static String _whyEasy(Map<String, dynamic> match) {
    final why = _trimWhy((match['why_easy'] ?? '').toString());
    if (why.isNotEmpty) return why;
    final count = pairMedicines(match).length;
    final opener = switch (count) {
      3 => '세 약을 같이 드시면, ',
      4 => '네 약을 같이 드시면, ',
      _ => '두 약을 같이 드시면, ',
    };
    final body = switch ((match['type'] ?? '').toString()) {
      '중복성분' => '같은 성분이 들어 있어서, 양이 겹칩니다.',
      '효능군중복' => '비슷한 일을 해서, 효과가 겹칩니다.',
      _ => '몸에 부담이 겹칠 수 있어요. 약국이나 병원에 한 번 확인해 주세요.',
    };
    return _trimWhy('$opener$body');
  }

  /// 분홍 상자 맨 윗줄. 첫 문장만 굵게 읽힌다.
  static String _whyHeadline(String why) {
    final cut = why.indexOf('. ');
    if (cut < 0) return why;
    return why.substring(0, cut + 1);
  }

  /// 첫 문장 뒤에 남는 설명. 없으면 빈 글자.
  static String _whyDetail(String why) {
    final cut = why.indexOf('. ');
    if (cut < 0) return '';
    return why.substring(cut + 2).trim();
  }

  static String _trimWhy(String raw) {
    var text = raw.trim();
    const openers = [
      '두 약을 같이 드시면, ',
      '세 약을 같이 드시면, ',
      '네 약을 같이 드시면, ',
      '다섯 약을 같이 드시면, ',
    ];
    for (final opener in openers) {
      if (text.startsWith(opener)) {
        text = text.substring(opener.length);
        break;
      }
    }
    text = text.replaceAll('약국이나 병원에 한 번 확인해 주세요.', '').trim();
    return text;
  }

  static String _sourceLabel(Map<String, dynamic> match) {
    final label = (match['source_label'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;
    return switch ((match['type'] ?? '').toString()) {
      '병용금기' => '식약처 DUR 병용금기 참조',
      '효능군중복' => '식약처 DUR 효능군중복 참조',
      '중복성분' => '같은 성분 중복 참조',
      _ => '식약처 DUR 참조',
    };
  }
}

class _NamedMedicine {
  final String name;
  const _NamedMedicine(this.name);
}
