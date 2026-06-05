import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/constants/app_colors.dart';

/// 기록 탭. 복약 달력 + 선택한 날짜의 복약 이력 + 복약 전후 심박 그래프(fl_chart).
/// (더미 데이터. 실제로는 Firestore 복약 기록으로 교체)
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// 0=완료, 1=일부 미복약
class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime _selected;
  late final DateTime _month;
  final Map<int, int> _status = {
    1: 0,
    2: 0,
    3: 1,
    4: 0,
    5: 0,
    6: 0,
    7: 0,
    8: 0,
    9: 1,
    10: 0,
    11: 0,
    12: 0,
    13: 0,
    14: 0,
    15: 0,
    16: 0,
    17: 0,
    18: 0,
  };

  // 더미: 점심 복약(12:00) 전후 심박 (11:30~12:40, 도즈는 index 6)
  static const List<double> _doseHr = [
    74,
    75,
    74,
    73,
    74,
    75,
    78,
    81,
    80,
    79,
    78,
    77,
    76,
  ];
  static const int _doseIndex = 6;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _selected = now;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          '복약 기록',
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
            Row(
              children: const [
                _SummaryBox(label: '이번 달 복약률', value: '94%', color: kPrimary),
                SizedBox(width: 10),
                _SummaryBox(
                  label: '미복약',
                  value: '2회',
                  color: Color(0xFFE6A100),
                ),
                SizedBox(width: 10),
                _SummaryBox(
                  label: '이상 감지',
                  value: '0회',
                  color: Color(0xFF4CAF50),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 달력
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDeco(),
              child: Column(
                children: [
                  Text(
                    '${_month.year}년 ${_month.month}월',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: const ['일', '월', '화', '수', '목', '금', '토']
                        .map(
                          (d) => Expanded(
                            child: Center(
                              child: Text(
                                d,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  _buildCalendarGrid(),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      _Legend(color: kPrimary, label: '복약 완료'),
                      SizedBox(width: 14),
                      _Legend(color: Color(0xFFE6A100), label: '일부 미복약'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            Text(
              '${_selected.month}월 ${_selected.day}일 상세',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kText,
              ),
            ),
            const SizedBox(height: 10),
            _dayDetail(),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = _month.weekday % 7;
    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final isSelected = day == _selected.day;
      final status = _status[day];
      Color? dot;
      if (status == 0) dot = kPrimary;
      if (status == 1) dot = const Color(0xFFE6A100);
      cells.add(
        GestureDetector(
          onTap: () => setState(
            () => _selected = DateTime(_month.year, _month.month, day),
          ),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected ? kPrimaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected ? kPrimary : kText,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: dot ?? Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      rows.add(
        Row(
          children: List.generate(7, (j) {
            final idx = i + j;
            return Expanded(
              child: SizedBox(
                height: 44,
                child: idx < cells.length ? cells[idx] : const SizedBox(),
              ),
            );
          }),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _dayDetail() {
    final times = const [
      {'time': '아침 08:00', 'pills': '암로디핀, 아스피린', 'done': true},
      {'time': '점심 12:00', 'pills': '메트포르민', 'done': true},
      {'time': '저녁 18:00', 'pills': '메트포르민, 암로디핀', 'done': true},
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        children: [
          ...times.map((t) {
            final done = t['done'] as bool;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(
                    done ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: done ? kPrimary : const Color(0xFFE6A100),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['time'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kText,
                          ),
                        ),
                        Text(
                          t['pills'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    done ? '완료' : '미복약',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: done ? kPrimary : const Color(0xFFE6A100),
                    ),
                  ),
                ],
              ),
            );
          }),
          const Divider(height: 16),
          // 복약 전후 심박 그래프
          Row(
            children: [
              const Text('💓', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              const Text(
                '점심 복약 전후 심박',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF534AB7),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '정상',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: 120, child: LineChart(_doseChartData())),
          const SizedBox(height: 4),
          Text(
            '세로 점선이 복약 시점이에요 (74 → 80 bpm)',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  LineChartData _doseChartData() {
    final spots = <FlSpot>[
      for (int i = 0; i < _doseHr.length; i++) FlSpot(i.toDouble(), _doseHr[i]),
    ];
    return LineChartData(
      minX: 0,
      maxX: (_doseHr.length - 1).toDouble(),
      minY: 60,
      maxY: 95,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(show: false),
      // 복약 시점 세로 점선
      extraLinesData: ExtraLinesData(
        verticalLines: [
          VerticalLine(
            x: _doseIndex.toDouble(),
            color: const Color(0xFF534AB7),
            strokeWidth: 1.5,
            dashArray: [4, 4],
          ),
        ],
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
          color: const Color(0xFF534AB7),
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF534AB7).withValues(alpha: 0.10),
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

class _SummaryBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
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
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}
