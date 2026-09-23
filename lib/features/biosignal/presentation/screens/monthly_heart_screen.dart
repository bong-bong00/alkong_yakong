import 'package:flutter/material.dart';
import '../../../medication/application/medication_controller.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../domain/heart_data.dart';
import '../widgets/heart_readings_card.dart';

/// 26 · 한 달 기록.
///
/// **주 단위로 묶어 보여준다.** 30일 × 2회를 막대 60개로 그리지 않는다.
/// 대신 "며칠째 정상인가"와 "이상했던 날 하나"를 앞세운다.
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

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final measured = data.month.any((d) => !d.isMissing);
    final readings = data.readingsFor(monthly: true);
    // 가족에게 보내는 설정일 때만 호칭을 찾는다. 연결이 없으면 "같이 보고
    // 있어요"라고 말하지 않는다 — 없는 사람을 지어내지 않는다.
    final guardianTitle = data.notifyGuardian
        ? resolveGuardianTitle(context, widget.guardianTitle)
        : '';
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (readings.isNotEmpty) ...[
                    HeartReadingsCard(
                      readings: readings,
                      hasComparison: measured,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!measured)
                    _EmptyMonthCard(month: _month)
                  else ...[
                    _MonthSummaryCard(data: data, month: _month),
                    const SizedBox(height: 12),
                    _WeeklyBars(days: data.month),
                    if (data.anomaly != null) ...[
                      const SizedBox(height: 12),
                      _AnomalyCard(
                        anomaly: data.anomaly!,
                        month: _month,
                        guardianTitle: guardianTitle.isEmpty
                            ? '가족'
                            : guardianTitle,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 이번 달에 잰 날이 하나도 없을 때.
class _EmptyMonthCard extends StatelessWidget {
  final int month;
  const _EmptyMonthCard({required this.month});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          const ExcludeSemantics(
            child: Icon(
              TablerIcons.calendar_off,
              size: 40,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$month월에는 아직 측정 기록이 없어요',
            textAlign: TextAlign.center,
            style: AppText.cardTitle(size: 21),
          ),
          const SizedBox(height: 6),
          Text(
            '약 먹기 전·후로 재면 날짜별로 여기에 모여요.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 최근에 **잰** 날 열흘까지. 빨랐던 날은 붉게, 정상인 날은 파랗게.
///

/// 한 번 빠르게 뛴 날.
class _AnomalyCard extends StatelessWidget {
  final HeartAnomaly anomaly;
  final int month;
  final String guardianTitle;

  const _AnomalyCard({
    required this.anomaly,
    required this.month,
    required this.guardianTitle,
  });

  @override
  Widget build(BuildContext context) {
    final slot = anomaly.slotLabel.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(22)),
        border: Border(left: BorderSide(color: AppColors.danger, width: 6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('한 번 빠른 날이 있었어요', style: AppText.cardTitle(size: 19.5)),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: AppText.body(size: 18),
              children: [
                TextSpan(
                  text:
                      '$month월 ${anomaly.day}일'
                      '${slot.isEmpty ? '' : ' $slot'}, 약 먹은 뒤 ',
                ),
                TextSpan(
                  text: '${anomaly.after}회',
                  style: AppText.body(
                    size: 18,
                    color: AppColors.danger,
                    weight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: '였어요. (먹기 전 ${anomaly.before}회)'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthSummaryCard extends StatelessWidget {
  final HeartData data;
  final int month;

  const _MonthSummaryCard({required this.data, required this.month});

  /// 잰 날만 세어 평균 낙폭을 구한다. 못 잰 날을 0으로 치지 않는다.
  int get _drop {
    final drops = <int>[
      for (final day in data.month)
        if (day.pair.before != null && day.pair.after != null)
          day.pair.before! - day.pair.after!,
    ];
    if (drops.isEmpty) return 0;
    return (drops.reduce((a, b) => a + b) / drops.length).round();
  }

  @override
  Widget build(BuildContext context) {
    final drop = _drop;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.point,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$month월 한 달',
            style: AppText.label(size: 17.5, color: AppColors.onPointMuted),
          ),
          const SizedBox(height: 6),
          Text(
            drop > 0 ? '약 드신 뒤 평균 $drop회 내려갔어요' : '약 드신 뒤에도 비슷했어요',
            style: AppText.emphasis(size: 24, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// 주마다 변화 — 약 먹기 전(회색)과 먹은 뒤(파랑)를 주 단위로 나란히 본다.
class _WeeklyBars extends StatelessWidget {
  final List<HeartMonthDay> days;

  const _WeeklyBars({required this.days});

  /// 한 주(7일)씩 묶어 전·후 평균을 낸다. 잰 날이 없는 주는 건너뛴다.
  List<_WeekAverage> get _weeks {
    final result = <_WeekAverage>[];
    for (int start = 0; start < days.length; start += 7) {
      final chunk = days.skip(start).take(7);
      final before = <int>[
        for (final day in chunk)
          if (day.pair.before != null) day.pair.before!,
      ];
      final after = <int>[
        for (final day in chunk)
          if (day.pair.after != null) day.pair.after!,
      ];
      if (before.isEmpty && after.isEmpty) continue;
      result.add(
        _WeekAverage(
          week: start ~/ 7 + 1,
          before: before.isEmpty
              ? null
              : (before.reduce((a, b) => a + b) / before.length).round(),
          after: after.isEmpty
              ? null
              : (after.reduce((a, b) => a + b) / after.length).round(),
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _weeks;
    if (weeks.isEmpty) return const SizedBox.shrink();
    final highest = weeks
        .expand((w) => [w.before ?? 0, w.after ?? 0])
        .reduce((a, b) => a > b ? a : b);
    final allDropped = weeks.every(
      (w) => w.before == null || w.after == null || w.after! <= w.before!,
    );

    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text('주마다 변화', style: AppText.cardTitle())),
              const SizedBox(width: 10),
              const Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _BarLegend(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final week in weeks)
                  Expanded(
                    child: _WeekPair(week: week, highest: highest),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final week in weeks)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${week.after ?? week.before ?? '–'}',
                        textAlign: TextAlign.center,
                        style: AppText.cardTitle(
                          size: 18,
                          color: AppColors.point,
                        ),
                      ),
                      Text(
                        '${week.week}주',
                        textAlign: TextAlign.center,
                        style: AppText.caption(size: 16),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            allDropped
                ? '파란 막대가 회색보다 늘 낮아요. 약을 드신 뒤 심박수가 내려갔다는 뜻이에요.'
                : '어떤 주는 약을 드신 뒤에도 비슷했어요.',
            style: AppText.body(size: 17, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 한 주의 전·후 평균.
class _WeekAverage {
  final int week;
  final int? before;
  final int? after;

  const _WeekAverage({required this.week, this.before, this.after});
}

/// 한 주의 막대 두 개 — 왼쪽이 먹기 전, 오른쪽이 먹은 뒤.
class _WeekPair extends StatelessWidget {
  final _WeekAverage week;
  final int highest;

  const _WeekPair({required this.week, required this.highest});

  double _height(int? value) {
    if (value == null || highest == 0) return 8;
    return 24 + (value / highest) * 84;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Bar(height: _height(week.before), color: AppColors.secondaryFill),
        const SizedBox(width: 5),
        _Bar(height: _height(week.after), color: AppColors.point),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double height;
  final Color color;

  const _Bar({required this.height, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}

/// 막대 두 색이 무엇인지 알려 주는 표시.
class _BarLegend extends StatelessWidget {
  const _BarLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _LegendDot(color: AppColors.secondaryFill, label: '전'),
        SizedBox(width: 10),
        _LegendDot(color: AppColors.point, label: '후'),
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
        const SizedBox(width: 5),
        Text(label, style: AppText.caption(size: 16)),
      ],
    );
  }
}
