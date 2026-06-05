import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/constants/app_colors.dart';

/// 생체신호 탭. 폴라 센서 연속 심박 데이터를 fl_chart 로 보여준다.
/// (더미 데이터. 실제 폴라 BLE 연동 시 _hrSamples 교체)
class BiosignalScreen extends StatelessWidget {
  const BiosignalScreen({super.key});

  // 더미: 깨어있는 시간(08~20시) 심박수 샘플 (36포인트)
  static const List<double> _hrSamples = [
    72,
    74,
    73,
    75,
    78,
    76,
    74,
    73,
    75,
    77,
    80,
    82,
    79,
    77,
    75,
    74,
    76,
    78,
    81,
    83,
    80,
    78,
    76,
    75,
    77,
    79,
    82,
    80,
    78,
    76,
    77,
    79,
    80,
    78,
    77,
    78,
  ];
  static const double _baselineLow = 70;
  static const double _baselineHigh = 82;

  static const Color _polar = Color(0xFF534AB7);
  static const Color _polarBg = Color(0xFFEDE8F5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          '생체신호',
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
            // 센서 상태 + 현재 심박
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _polarBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFC8B8E0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Text('💓', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 8),
                      Text(
                        '폴라 센서 연결됨',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _polar,
                        ),
                      ),
                      Spacer(),
                      Icon(
                        Icons.battery_5_bar_rounded,
                        size: 16,
                        color: _polar,
                      ),
                      SizedBox(width: 2),
                      Text(
                        '84%',
                        style: TextStyle(fontSize: 12, color: _polar),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        '78',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          color: _polar,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'bpm',
                          style: TextStyle(fontSize: 15, color: _polar),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '정상 범위',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 오늘 심박수 그래프 (fl_chart)
            const _SectionTitle('📈', '오늘 심박수'),
            const SizedBox(height: 4),
            Text(
              '그래프를 누르면 그 시점 심박수가 표시돼요',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 18, 16, 12),
              decoration: _cardDeco(),
              child: Column(
                children: [
                  SizedBox(height: 180, child: LineChart(_chartData())),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const _LegendDot(color: kPrimary, label: '측정값'),
                      const SizedBox(width: 16),
                      const _LegendDot(
                        color: Color(0xFFB7E4CF),
                        label: '정상 범위 (70~82)',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 통계
            Row(
              children: const [
                Expanded(
                  child: _StatBox(label: '평균', value: '77', unit: 'bpm'),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _StatBox(label: '최고', value: '83', unit: 'bpm'),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _StatBox(label: '최저', value: '72', unit: 'bpm'),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _StatBox(label: 'HRV', value: '42', unit: 'ms'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 복약 후 변화
            const _SectionTitle('💊', '복약 후 심박 변화'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: _cardDeco(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '점심 복약 (12:00)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '정상 반응',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: const [
                      _BeforeAfter(label: '복약 전', value: '74'),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.grey,
                        size: 20,
                      ),
                      _BeforeAfter(label: '복약 후', value: '80'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '복약 후 심박이 6bpm 상승했으나 정상 범위 이내이고 10분 내 안정화되어 이상 없음으로 판단했어요.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _chartData() {
    final spots = <FlSpot>[
      for (int i = 0; i < _hrSamples.length; i++)
        FlSpot(i.toDouble(), _hrSamples[i]),
    ];

    return LineChartData(
      minX: 0,
      maxX: (_hrSamples.length - 1).toDouble(),
      minY: 55,
      maxY: 110,
      // 정상 범위 밴드
      rangeAnnotations: RangeAnnotations(
        horizontalRangeAnnotations: [
          HorizontalRangeAnnotation(
            y1: _baselineLow,
            y2: _baselineHigh,
            color: const Color(0xFFEAF7F1),
          ),
        ],
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 20,
        getDrawingHorizontalLine: (v) =>
            const FlLine(color: Color(0xFFEDEDED), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 20,
            getTitlesWidget: (value, meta) {
              if (value == 60 || value == 80 || value == 100) {
                return Text(
                  '${value.toInt()}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              String? t;
              if (i == 0) t = '08시';
              if (i == 12) t = '12시';
              if (i == 24) t = '16시';
              if (i == 35) t = '20시';
              if (t == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  t,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) => touchedSpots
              .map(
                (s) => LineTooltipItem(
                  '${s.y.toInt()} bpm',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              )
              .toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: kPrimary,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: kPrimary.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }

  static BoxDecoration _cardDeco() => BoxDecoration(
    color: kCard,
    borderRadius: BorderRadius.circular(18),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  final String emoji;
  final String text;
  const _SectionTitle(this.emoji, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: kText,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _StatBox({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
          ),
          Text(unit, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
        ],
      ),
    );
  }
}

class _BeforeAfter extends StatelessWidget {
  final String label;
  final String value;
  const _BeforeAfter({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: kText,
              ),
              children: const [
                TextSpan(
                  text: ' bpm',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
