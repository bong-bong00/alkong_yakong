import 'package:flutter/material.dart';

import '../../../../core/polar_pharmacist_ui/constants/app_colors.dart';
import '../../../../core/polar_pharmacist_ui/theme/app_typography.dart';
import '../../../../core/polar_pharmacist_ui/widgets/senior_card.dart';
import '../../../../core/polar_pharmacist_ui/widgets/senior_feedback.dart';
import '../../../../core/polar_pharmacist_ui/widgets/senior_header.dart';
import '../../domain/heart_data.dart';
import '../widgets/heart_readings_card.dart';

/// 26 · 한 달 기록.
///
/// 명시적으로 복약 전·후라고 저장된 기록만 비교한다. 일반 측정이나
/// 측정 시각으로 전·후를 추정하지 않는다.
///
/// [data]는 심박수 관리 화면이 서버에서 읽어 넘겨준 것만 받는다.
/// 잰 날이 하나도 없으면 "0일째 정상"을 그리지 않고 기록이 없다고 말한다.
class MonthlyHeartScreen extends StatefulWidget {
  final HeartData data;
  final String guardianTitle;

  /// 날짜에 붙일 "몇 월". 서버는 이번 달 날짜만 보내므로 기본은 오늘이다.
  /// 테스트에서 날짜를 고정할 때만 넘긴다.
  final DateTime? now;

  const MonthlyHeartScreen({
    super.key,
    required this.data,
    this.guardianTitle = '',
    this.now,
  });

  @override
  State<MonthlyHeartScreen> createState() => _MonthlyHeartScreenState();
}

class _MonthlyHeartScreenState extends State<MonthlyHeartScreen> {
  late final int _month = (widget.now ?? DateTime.now()).month;
  bool _showAllReadings = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final readings = data.readingsFor(monthly: true);
    final comparison = _MonthlyComparison.fromReadings(readings);
    final newestFirst = List<HeartReading>.of(readings)
      ..sort((a, b) {
        final byTime = b.measuredAt.compareTo(a.measuredAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SeniorBackButton(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '한 달 기록',
                        style: AppText.screenTitle(size: 24),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SeniorSegmented(
                  labels: const ['이번 주', '한 달'],
                  index: 1,
                  onChanged: (i) {
                    if (i == 0) Navigator.of(context).maybePop();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            // 헤더와 탭 아래의 별도 viewport로 제한해 기록이 상단 영역
            // 뒤에 그려지지 않게 한다.
            child: ClipRect(
              child: SingleChildScrollView(
                key: const Key('monthly-heart-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 잰 날이 없어도 달력은 그린다 — 며칠에 쟀는지를
                    // 한눈에 보는 자리이기 때문이다.
                    _MonthCalendarCard(
                      month: _month,
                      measured: {
                        for (final reading in readings)
                          if (reading.measuredAt.toLocal().month == _month)
                            reading.measuredAt.toLocal().day,
                      },
                    ),
                    const SizedBox(height: 12),
                    // 잰 것이 없어도 그래프 자리는 그대로 둔다. 자리가
                    // 사라지면 어제 보던 것이 어디 갔는지부터 찾게 된다.
                    _DailyBars(month: _month, readings: readings),
                    if (readings.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      HeartReadingsCard(
                        readings: _showAllReadings
                            ? newestFirst
                            : newestFirst.take(2).toList(growable: false),
                        hasComparison: comparison.pairCount > 0,
                      ),
                      if (newestFirst.length > 2)
                        TextButton.icon(
                          key: const Key('monthly-heart-toggle-readings'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.point,
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: () => setState(
                            () => _showAllReadings = !_showAllReadings,
                          ),
                          icon: Icon(
                            _showAllReadings
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                          ),
                          label: Text(
                            _showAllReadings ? '접기' : '이전 기록 더 보기',
                            style: AppText.label(size: 18),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 한 달 달력. 잰 날에 파란 동그라미를 둔다.
class _MonthCalendarCard extends StatelessWidget {
  final int month;

  /// 측정한 날(일).
  final Set<int> measured;

  const _MonthCalendarCard({required this.month, required this.measured});

  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final first = DateTime(now.year, month, 1);
    final days = DateUtils.getDaysInMonth(now.year, month);
    // 일요일을 0으로 센다. DateTime은 월요일이 1, 일요일이 7이다.
    final lead = first.weekday % 7;
    final cells = lead + days;
    final rows = (cells / 7).ceil();

    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('$month월', style: AppText.cardTitle(size: 21)),
          ),
          Row(
            children: [
              for (final name in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      name,
                      style: AppText.caption(
                        size: 15,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (int row = 0; row < rows; row++)
            Row(
              children: [
                for (int col = 0; col < 7; col++)
                  Expanded(
                    child: _Cell(
                      day: row * 7 + col - lead + 1,
                      days: days,
                      measured: measured,
                      today: now.month == month ? now.day : null,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 달력 한 칸.
class _Cell extends StatelessWidget {
  final int day;
  final int days;
  final Set<int> measured;
  final int? today;

  const _Cell({
    required this.day,
    required this.days,
    required this.measured,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    if (day < 1 || day > days) return const SizedBox(height: 44);
    final marked = measured.contains(day);
    final isToday = day == today;

    // 복약 달력과 같은 규칙 — 오늘은 검정, 기록이 있는 날은 연한 파랑,
    // 나머지는 비워 둔다.
    final Color background;
    final Color ink;
    if (isToday) {
      background = AppColors.textPrimary;
      ink = Colors.white;
    } else if (marked) {
      background = AppColors.pointTint;
      ink = AppColors.pointBorder;
    } else {
      background = Colors.transparent;
      ink = AppColors.chevron;
    }

    return Semantics(
      label: ['$day일', if (isToday) '오늘', if (marked) '측정했어요'].join(' '),
      child: ExcludeSemantics(
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: Text('$day', style: AppText.body(size: 17, color: ink)),
          ),
        ),
      ),
    );
  }
}

/// 날마다 복약 전·후 심박수.
///
/// 한 달 치를 가로로 늘어놓고, 잰 날에만 막대를 세운다. **잰 것이 하나도
/// 없어도 이 칸은 그린다** — 자리가 통째로 사라지면 기록이 없는 것인지
/// 화면이 잘못된 것인지 알 수 없다.
class _DailyBars extends StatelessWidget {
  final int month;
  final List<HeartReading> readings;

  const _DailyBars({required this.month, required this.readings});

  @override
  Widget build(BuildContext context) {
    final byDay = <int, _DayMeasurements>{};
    for (final reading in readings) {
      final at = reading.measuredAt.toLocal();
      if (at.month != month) continue;
      final values = byDay.putIfAbsent(
        at.day,
        () => _DayMeasurements(DateTime(at.year, at.month, at.day)),
      );
      switch (reading.measurementContext) {
        case HeartMeasurementContext.beforeMedication:
          values.before.add(reading.bpm);
        case HeartMeasurementContext.afterMedication:
          values.after.add(reading.bpm);
        case HeartMeasurementContext.general:
          break;
      }
    }

    final year = readings.isEmpty
        ? DateTime.now().year
        : readings.first.measuredAt.toLocal().year;
    final dayCount = DateTime(year, month + 1, 0).day;
    final allValues = [
      for (final values in byDay.values) ...values.before,
      for (final values in byDay.values) ...values.after,
    ];
    final highest = allValues.isEmpty
        ? 0
        : allValues.reduce((a, b) => a > b ? a : b);

    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('날마다 복약 전·후', style: AppText.cardTitle()),
          const SizedBox(height: 6),
          Text(
            allValues.isEmpty
                ? '$month월에는 아직 잰 기록이 없어요'
                : '단위: 회/분 · 잰 날 ${byDay.length}일',
            style: AppText.caption(size: 16),
          ),
          const SizedBox(height: 10),
          const _BarLegend(),
          const SizedBox(height: 16),
          SingleChildScrollView(
            key: const Key('daily-heart-bars'),
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int day = 1; day <= dayCount; day++)
                  _DayPair(
                    day: day,
                    before: byDay[day]?.before.isEmpty ?? true
                        ? null
                        : _average(byDay[day]!.before),
                    after: byDay[day]?.after.isEmpty ?? true
                        ? null
                        : _average(byDay[day]!.after),
                    highest: highest,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 하루치 막대 둘. 안 잰 쪽은 바닥선만 남긴다.
class _DayPair extends StatelessWidget {
  final int day;
  final int? before;
  final int? after;
  final int highest;

  const _DayPair({
    required this.day,
    required this.before,
    required this.after,
    required this.highest,
  });

  double _height(int? value) {
    if (value == null || highest == 0) return 3;
    return 18 + (value / highest) * 76;
  }

  @override
  Widget build(BuildContext context) {
    final measured = before != null || after != null;
    return Semantics(
      label: measured
          ? '$day일 복약 전 ${before ?? '없음'} 복약 후 ${after ?? '없음'}'
          : '$day일 잰 기록 없음',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 44,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 112,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Bar(
                      value: before,
                      height: _height(before),
                      color: before == null
                          ? AppColors.divider
                          : AppColors.secondaryFill,
                    ),
                    const SizedBox(width: 4),
                    _Bar(
                      value: after,
                      height: _height(after),
                      color: after == null
                          ? AppColors.divider
                          : AppColors.point,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$day',
                style: AppText.caption(
                  size: 15,
                  color: measured
                      ? AppColors.textSecondary
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 한 주의 전·후 평균.
class _WeekAverage {
  final DateTime start;
  final int before;
  final int after;

  const _WeekAverage({
    required this.start,
    required this.before,
    required this.after,
  });

  DateTime get end => start.add(const Duration(days: 6));

  String get periodLabel =>
      '${start.month}/${start.day}~${end.month}/${end.day}';
}

class _Bar extends StatelessWidget {
  final double height;
  final Color color;
  final int? value;

  const _Bar({required this.height, required this.color, this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          if (value != null && (value! < 60 || value! > 100))
            Positioned(
              bottom: height + 2,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 16,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$value',
                    key: Key('heart-bar-value-$value'),
                    style: AppText.label(size: 12),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 막대 두 색이 무엇인지 알려 주는 표시.
class _BarLegend extends StatelessWidget {
  const _BarLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: const [
        _LegendDot(color: AppColors.secondaryFill, label: '복약 전'),
        _LegendDot(color: AppColors.point, label: '복약 후'),
      ],
    );
  }
}

class _MonthlyComparison {
  final List<_DailyPair> pairs;
  final List<_WeekAverage> weeks;

  const _MonthlyComparison({required this.pairs, required this.weeks});

  int get pairCount => pairs.length;

  int get beforeAverage => _average(pairs.map((pair) => pair.before));
  int get afterAverage => _average(pairs.map((pair) => pair.after));

  String get changeSummary {
    final difference = afterAverage - beforeAverage;
    if (difference > 0) return '$difference회/분 높았어요';
    if (difference < 0) return '${difference.abs()}회/분 낮았어요';
    return '복약 전과 같았어요';
  }

  static _MonthlyComparison fromReadings(List<HeartReading> readings) {
    final days = <int, _DayMeasurements>{};
    for (final reading in readings) {
      if (reading.measurementContext == HeartMeasurementContext.general) {
        continue;
      }
      final at = reading.measuredAt.toLocal();
      final date = DateTime(at.year, at.month, at.day);
      final key = at.year * 10000 + at.month * 100 + at.day;
      final values = days.putIfAbsent(key, () => _DayMeasurements(date));
      if (reading.measurementContext ==
          HeartMeasurementContext.beforeMedication) {
        values.before.add(reading.bpm);
      } else if (reading.measurementContext ==
          HeartMeasurementContext.afterMedication) {
        values.after.add(reading.bpm);
      }
    }

    final pairs = <_DailyPair>[
      for (final values in days.values)
        if (values.before.isNotEmpty && values.after.isNotEmpty)
          _DailyPair(
            date: values.date,
            before: _average(values.before),
            after: _average(values.after),
          ),
    ]..sort((a, b) => a.date.compareTo(b.date));

    final groupedWeeks = <DateTime, List<_DailyPair>>{};
    for (final pair in pairs) {
      final start = pair.date.subtract(Duration(days: pair.date.weekday - 1));
      groupedWeeks.putIfAbsent(start, () => <_DailyPair>[]).add(pair);
    }
    final weeks = <_WeekAverage>[
      for (final entry in groupedWeeks.entries)
        _WeekAverage(
          start: entry.key,
          before: _average(entry.value.map((pair) => pair.before)),
          after: _average(entry.value.map((pair) => pair.after)),
        ),
    ]..sort((a, b) => a.start.compareTo(b.start));

    return _MonthlyComparison(pairs: pairs, weeks: weeks);
  }
}

class _DayMeasurements {
  final DateTime date;
  final List<int> before = <int>[];
  final List<int> after = <int>[];

  _DayMeasurements(this.date);
}

class _DailyPair {
  final DateTime date;
  final int before;
  final int after;

  const _DailyPair({
    required this.date,
    required this.before,
    required this.after,
  });
}

int _average(Iterable<int> values) {
  final list = values.toList();
  if (list.isEmpty) {
    throw StateError('Cannot average an empty heart-rate set.');
  }
  return (list.reduce((a, b) => a + b) / list.length).round();
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
        const SizedBox(width: 5),
        Text(label, style: AppText.caption(size: 16)),
      ],
    );
  }
}
