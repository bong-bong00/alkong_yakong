import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/constants/app_colors.dart';

/// 심박 이상 이벤트 상세 화면.
/// 알림 탭(또는 생체신호 화면)에서 "심박 이상" 이벤트를 누르면 진입.
/// 이벤트 발생 전후 심박 추이를 그래프로 보여준다.
/// 위치: lib/features/dashboard/presentation/screens/biosignal_event_screen.dart
class BiosignalEventScreen extends StatelessWidget {
  final Color accent;
  final String patientName;

  const BiosignalEventScreen({
    super.key,
    this.accent = kGuardian,
    this.patientName = '김복자',
  });

  static const _danger = Color(0xFFE24B4A);

  // TODO: 백엔드 생체신호 이벤트 API로 교체. 현재는 데모 데이터.
  // 14:00부터 2분 간격 심박 샘플 (빈맥 발생 후 회복)
  List<int> get _hr => const [
    72,
    74,
    73,
    75,
    78,
    84,
    96,
    112,
    125,
    121,
    116,
    104,
    92,
    84,
    79,
    76,
    74,
    73,
  ];
  String get _startTime => '14:00';
  String get _peakTime => '14:16';
  int get _peakBpm => 125;
  String get _eventType => '빈맥 (빠른 맥박)';
  String get _duration => '약 8분';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '심박 이상 이벤트',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            // ── 요약 카드 ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _danger.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('💓', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Text(
                        _eventType,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: kText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$patientName님 · 오늘 $_peakTime 발생',
                    style: TextStyle(fontSize: 13.5, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _metric('최고 심박', '$_peakBpm', 'bpm', _danger),
                      const SizedBox(width: 12),
                      _metric('지속 시간', _duration, '', kText),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 그래프 ──
            const Text(
              '심박 추이',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: kText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$_startTime ~ 회복까지 · 2분 간격',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 18, 16, 10),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SizedBox(height: 200, child: _chart()),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legend(const Color(0xFFEAF7F1), '정상 범위 (60~100)'),
                const SizedBox(width: 16),
                _legend(_danger, '심박'),
              ],
            ),
            const SizedBox(height: 20),

            // ── 설명 ──
            _infoCard(
              icon: Icons.info_outline_rounded,
              title: '빈맥이란?',
              body:
                  '안정 상태에서 심박수가 분당 100회를 넘는 경우를 빈맥이라고 해요. '
                  '운동·카페인·긴장으로 일시적으로 생기기도 하지만, 자주 반복되면 '
                  '확인이 필요해요.',
            ),
            const SizedBox(height: 10),
            _infoCard(
              icon: Icons.medical_services_outlined,
              title: '이럴 땐 상담을 권해요',
              body:
                  '안정 시에도 빠른 맥박이 자주 나타나거나, 어지럼·가슴 두근거림·'
                  '호흡곤란이 함께 있으면 의사·약사와 상담하는 것이 좋아요.',
              accent: accent,
            ),
          ],
        ),
      ),
    );
  }

  // ── fl_chart 라인 차트 ──
  Widget _chart() {
    final spots = [
      for (int i = 0; i < _hr.length; i++)
        FlSpot(i.toDouble(), _hr[i].toDouble()),
    ];
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (_hr.length - 1).toDouble(),
        minY: 60,
        maxY: 140,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: const Color(0xFFEDEDED), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 20,
              reservedSize: 34,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 4,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                final minutes = i * 2;
                final label = '14:${minutes.toString().padLeft(2, '0')}';
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                  ),
                );
              },
            ),
          ),
        ),
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: [
            HorizontalRangeAnnotation(
              y1: 60,
              y2: 100,
              color: const Color(0xFFEAF7F1),
            ),
          ],
        ),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: _danger,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: _danger.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, String unit, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(
                    unit,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String body,
    Color? accent,
  }) {
    final c = accent ?? kTextSub;
    return Container(
      width: double.infinity,
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
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: c),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: kText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.grey[700],
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
