import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// DUR(병용금기·중복성분) 위험도 상세. 약정보 탭 배너에서 push.
/// (더미. 실제로는 FastAPI /drug/dur-check 결과)
class DurAnalysisScreen extends StatelessWidget {
  const DurAnalysisScreen({super.key});

  // 더미: 검사한 약 조합
  static const List<Map<String, String>> _pairs = [
    {
      'a': '암로디핀 5mg',
      'b': '메트포르민 500mg',
      'level': 'LOW',
      'reason': '함께 복용해도 문제없어요.',
    },
    {
      'a': '암로디핀 5mg',
      'b': '아스피린 100mg',
      'level': 'LOW',
      'reason': '함께 복용해도 문제없어요.',
    },
    {
      'a': '메트포르민 500mg',
      'b': '아스피린 100mg',
      'level': 'LOW',
      'reason': '함께 복용해도 문제없어요.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          '복약 안전도',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [kPrimary, Color(0xFF25B88A)]),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 전체 위험도
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFB7E4CF)),
              ),
              child: Column(
                children: [
                  const Text('🛡️', style: TextStyle(fontSize: 36)),
                  const SizedBox(height: 10),
                  const Text(
                    '전체 위험도: 안전',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '복용 중인 약 3개를 검사했어요.\n병용금기나 중복 성분이 없어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green[800],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            const Text(
              '검사한 약 조합',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kText,
              ),
            ),
            const SizedBox(height: 10),
            ..._pairs.map(
              (p) => _PairRow(
                a: p['a']!,
                b: p['b']!,
                level: p['level']!,
                reason: p['reason']!,
              ),
            ),
            const SizedBox(height: 22),

            // 범례
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '위험도 단계',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kText,
                    ),
                  ),
                  SizedBox(height: 12),
                  _LegendRow(
                    level: 'HIGH',
                    color: Color(0xFFE24B4A),
                    desc: '병용금기 — 함께 먹으면 위험해요',
                  ),
                  SizedBox(height: 10),
                  _LegendRow(
                    level: 'MEDIUM',
                    color: Color(0xFFE6A100),
                    desc: '중복 성분 — 같은 성분이 겹쳐요',
                  ),
                  SizedBox(height: 10),
                  _LegendRow(
                    level: 'LOW',
                    color: Color(0xFF4CAF50),
                    desc: '안전 — 함께 복용해도 괜찮아요',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PairRow extends StatelessWidget {
  final String a, b, level, reason;
  const _PairRow({
    required this.a,
    required this.b,
    required this.level,
    required this.reason,
  });

  Color get _color {
    switch (level) {
      case 'HIGH':
        return const Color(0xFFE24B4A);
      case 'MEDIUM':
        return const Color(0xFFE6A100);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: _color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$a  +  $b',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              level,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String level;
  final Color color;
  final String desc;
  const _LegendRow({
    required this.level,
    required this.color,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            level,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            desc,
            style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }
}
