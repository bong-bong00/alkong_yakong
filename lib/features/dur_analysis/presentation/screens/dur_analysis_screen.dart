import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';

/// 위험도 3단. **등급 숫자나 점수는 노출하지 않는다.**
enum DrugRisk {
  /// 위험 — 3px 위험색 테두리 카드.
  danger,

  /// 주의 — 테두리 + 본문 경고문.
  caution,

  /// 괜찮아요 — 안전 카드에 포함.
  safe,
}

/// 4f — 약 함께먹기 주의.
///
/// "DUR 분석"이라는 말을 쓰지 않는다. 어떤 약이 어떤 약과 부딪히는지,
/// 그래서 누구에게 물어봐야 하는지만 말한다.
class DurAnalysisScreen extends StatefulWidget {
  /// 함께 보고 있는 가족.
  final String guardianTitle;

  const DurAnalysisScreen({super.key, this.guardianTitle = '딸 지안 님'});

  @override
  State<DurAnalysisScreen> createState() => _DurAnalysisScreenState();
}

class _DurAnalysisScreenState extends State<DurAnalysisScreen> {
  final ApiClient _apiClient = ApiClient();

  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _matches = const [];

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _loading = true;
      _failed = false;
    });

    final userId = MvpSession.userId.trim();
    try {
      final response = await _apiClient.post(
        '/api/v1/dur/analyze',
        body: {'user_id': userId, 'medicine_codes': <String>[]},
      );
      if (!mounted) return;
      final matches = response is Map ? response['matches'] : null;
      setState(() {
        _matches = matches is List
            ? matches
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList()
            : const [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  static DrugRisk _riskOf(Map<String, dynamic> match) {
    final type = (match['type'] ?? match['taboo_type'] ?? '').toString();
    return switch (type) {
      '병용금기' || '중복성분' || '효능군중복' => DrugRisk.danger,
      '연령금기' || '임부금기' || '용량주의' || '투여기간주의' => DrugRisk.caution,
      _ => DrugRisk.safe,
    };
  }

  static String _pairOf(Map<String, dynamic> match) {
    final first = (match['ingredient_a'] ?? '').toString();
    final second = (match['ingredient_b'] ?? '').toString();
    if (first.isEmpty) return '등록하신 약';
    if (second.isEmpty) return first;
    return '$first과 $second';
  }

  /// 등록된 약 이름들 — 위험 목록에 없으면 "괜찮아요"에 들어간다.
  List<String> get _safeMedicines {
    final risky = <String>{};
    for (final match in _matches) {
      for (final key in ['ingredient_a', 'ingredient_b']) {
        final value = match[key]?.toString();
        if (value != null && value.isNotEmpty) risky.add(value);
      }
    }
    return [
      for (final item in MvpSession.latestOcrItems)
        if (item['drug_name'] != null &&
            !risky.contains(item['drug_name'].toString()))
          item['drug_name'].toString(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
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
        onAction: _analyze,
        stillWorksTitle: '약 알림은 그대로 와요',
        stillWorksBody: '인터넷이 끊겨도 복약 알림에는 영향이 없어요.',
        helperText: '그래도 안 되면\n${widget.guardianTitle}에게 도움 청하기',
        onCallHelper: _callGuardian,
      );
    }

    final dangers = _matches.where((m) => _riskOf(m) == DrugRisk.danger);
    final cautions = _matches.where((m) => _riskOf(m) == DrugRisk.caution);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final match in dangers) ...[
            _RiskCard(
              risk: DrugRisk.danger,
              headline: '${_pairOf(match)}을\n같이 드시면 위험해요',
              detail: match['reason']?.toString() ??
                  '두 약이 서로 부딪혀 몸에 무리가 갈 수 있어요. '
                      '약국에 전화해서 이 두 가지를 같이 먹어도 되는지 물어보세요.',
              onCall: _callPharmacy,
            ),
            const SizedBox(height: 12),
          ],
          for (final match in cautions) ...[
            _RiskCard(
              risk: DrugRisk.caution,
              headline: '${_pairOf(match)}은\n조심해서 드셔야 해요',
              detail: match['reason']?.toString() ??
                  '드시는 데 문제는 없지만, 몸이 평소와 다르면 약국에 물어보세요.',
              onCall: _callPharmacy,
            ),
            const SizedBox(height: 12),
          ],
          if (dangers.isEmpty && cautions.isEmpty) ...[
            SeniorCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('✅ 같이 드셔도 괜찮아요', style: AppText.emphasis()),
                  const SizedBox(height: 8),
                  Text(
                    '등록하신 약끼리 부딪히는 것이 없었어요. '
                    '지금처럼 드시면 돼요.',
                    style: AppText.body(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (_safeMedicines.isNotEmpty) ...[
            SeniorCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EmojiTitle(
                    emoji: '✅',
                    text: '나머지 약은 괜찮아요',
                    style: AppText.cardTitle(size: 19),
                  ),
                  const SizedBox(height: 10),
                  for (int i = 0; i < _safeMedicines.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: 10),
                      const SeniorDivider(),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.pointTint,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '✓',
                            style: AppText.label(
                              size: 18,
                              color: AppColors.point,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _safeMedicines[i],
                            style: AppText.label(
                              size: 19,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
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
                      EmojiTitle(
                        emoji: '💊',
                        text: '이 약은 무슨 약인가요?',
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
          const SizedBox(height: 16),

          SeniorButton(
            label: '${widget.guardianTitle}에게 알리기',
            kind: SeniorButtonKind.outline,
            minHeight: 64,
            fontSize: 21,
            onPressed: _callGuardian,
          ),
        ],
      ),
    );
  }

  void _callPharmacy() {
    // TODO: 등록된 약국 번호로 전화 연결.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('약국에 전화를 겁니다')));
  }

  void _callGuardian() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.guardianTitle}에게 알려드렸어요')),
    );
  }
}

class _RiskCard extends StatelessWidget {
  final DrugRisk risk;
  final String headline;
  final String detail;
  final VoidCallback onCall;

  const _RiskCard({
    required this.risk,
    required this.headline,
    required this.detail,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final isDanger = risk == DrugRisk.danger;
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      borderColor: isDanger ? AppColors.danger : AppColors.dangerBorder,
      borderWidth: isDanger ? 3 : 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SeniorBadge(
              label: isDanger ? '⚠️ 꼭 확인하세요' : '⚠️ 조심하세요',
              background: isDanger ? AppColors.danger : AppColors.dangerBorder,
              foreground: isDanger ? Colors.white : AppColors.danger,
              radius: 10,
              fontSize: 17,
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(headline, style: AppText.emphasis()),
          const SizedBox(height: 12),
          Text(detail, style: AppText.body()),
          const SizedBox(height: 12),
          SeniorButton(
            label: '약국에 전화하기',
            kind: SeniorButtonKind.danger,
            minHeight: 66,
            fontSize: 22,
            onPressed: onCall,
          ),
        ],
      ),
    );
  }
}
