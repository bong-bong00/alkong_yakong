import 'package:flutter/material.dart';
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
  /// 눌러서 펼친 날짜. 없으면 안내 문장을 보여준다.
  HeartMonthDay? _picked;

  late final int _month =
      (widget.now ?? widget.data.periodDate ?? DateTime.now()).month;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final hasComparison = data.month.any(
      (d) => d.pair.before != null || d.pair.after != null,
    );
    final readings = data.readingsFor(monthly: true);
    final measured = hasComparison || readings.isNotEmpty;
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
                        '심박수 관리',
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
                      hasComparison: data.month.any((d) => d.pair.isComplete),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!measured)
                    _EmptyMonthCard(month: _month)
                  else if (hasComparison) ...[
                    // 정상인 날이 이어지지 않았으면 "0일째"를 크게 쓰지 않는다.
                    if (data.streakDays > 0) ...[
                      _StreakCard(data: data),
                      const SizedBox(height: 12),
                    ],
                    if (data.anomaly != null) ...[
                      _AnomalyCard(
                        anomaly: data.anomaly!,
                        month: _month,
                        guardianTitle: widget.guardianTitle,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _DayGrid(
                      days: data.month,
                      month: _month,
                      picked: _picked,
                      onPick: (d) => setState(
                        () => _picked = _picked?.day == d.day ? null : d,
                      ),
                    ),
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
            '$month월에는 아직 잰 기록이 없어요',
            textAlign: TextAlign.center,
            style: AppText.cardTitle(size: 21),
          ),
          const SizedBox(height: 6),
          Text(
            '심박수를 재고 저장하면 날짜별로 여기에 모여요.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 며칠째 정상인지 — 이 화면의 주인공.
class _StreakCard extends StatelessWidget {
  final HeartData data;
  const _StreakCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        children: [
          Text(
            '지금까지',
            style: AppText.label(size: 19, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: '복약 후 심박 기록이 있는 날은 ${data.streakDays}일이에요',
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${data.streakDays}',
                    style: AppText.hero(size: 72, color: AppColors.point),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('일째', style: AppText.cardTitle(size: 24)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '복약 후 심박\n기록이 있어요',
            textAlign: TextAlign.center,
            style: AppText.cardTitle(size: 21),
          ),
          const SizedBox(height: 16),
          _RecentBars(days: data.month),
          const SizedBox(height: 12),
          Text(
            '가장 길었던 기록은 ${data.bestStreakDays}일이에요',
            textAlign: TextAlign.center,
            style: AppText.caption(size: 17.5),
          ),
        ],
      ),
    );
  }
}

/// 최근에 **잰** 날 열흘까지. 빨랐던 날은 붉게, 정상인 날은 파랗게.
///
/// 연속 일수로 칸 색을 거꾸로 지어내지 않는다 — 못 잰 날까지
/// "이상했던 날"로 칠하게 되기 때문이다. 실제 날짜별 값으로만 칠한다.
class _RecentBars extends StatelessWidget {
  final List<HeartMonthDay> days;
  const _RecentBars({required this.days});

  static const int _max = 10;

  @override
  Widget build(BuildContext context) {
    final measured = days.where((d) => !d.isMissing).toList();
    final recent = measured.length > _max
        ? measured.sublist(measured.length - _max)
        : measured;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < recent.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Container(
              width: 16,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.point,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
          Text('빠르게 뛴 날이 있었어요', style: AppText.cardTitle(size: 19.5)),
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
                    weight: FontWeight.w900,
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

/// 날짜별 격자. 먹은 뒤 수치만 보여주고, 누르면 전·후를 함께 편다.
class _DayGrid extends StatelessWidget {
  final List<HeartMonthDay> days;
  final int month;
  final HeartMonthDay? picked;
  final ValueChanged<HeartMonthDay> onPick;

  const _DayGrid({
    required this.days,
    required this.month,
    required this.picked,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('날짜별로 보기', style: AppText.cardTitle())),
              SeniorBadge(
                label: '먹은 후 수치',
                fontSize: 16.5,
                radius: 11,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 칸 높이를 계산하지 않고 내용에 맡긴다.
          // 글자 배율이 커지면 칸도 같이 자라야 잘리지 않는다.
          for (int row = 0; row < (days.length / 5).ceil(); row++) ...[
            if (row > 0) const SizedBox(height: 7),
            // 한 줄 안의 칸은 키를 맞춘다. 세로 스크롤 안이라 stretch만으로는
            // 높이가 무한이 되므로 IntrinsicHeight로 묶는다.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int col = 0; col < 5; col++) ...[
                    if (col > 0) const SizedBox(width: 7),
                    Expanded(
                      child: row * 5 + col < days.length
                          ? _DayCell(
                              day: days[row * 5 + col],
                              month: month,
                              selected: picked?.day == days[row * 5 + col].day,
                              onTap: () => onPick(days[row * 5 + col]),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (picked == null)
            Text(
              '날짜를 누르면 그날 먹기 전 수치까지 보여드려요',
              style: AppText.caption(size: 17.5),
            )
          else
            _PickedDetail(day: picked!, month: month),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final HeartMonthDay day;
  final int month;
  final bool selected;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.month,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final after = day.pair.after;
    final missing = day.isMissing;
    final Color background = missing ? AppColors.bg : AppColors.sunken;
    final Color valueColor = missing
        ? AppColors.chevron
        : AppColors.textPrimary;

    return Semantics(
      button: true,
      selected: selected,
      label: missing
          ? '$month월 ${day.day}일 재지 못했어요'
          : '$month월 ${day.day}일 먹은 후 $after회',
      child: GestureDetector(
        onTap: missing ? null : onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
              border: selected
                  ? Border.all(color: AppColors.point, width: 2)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${day.day}',
                  style: AppText.label(
                    size: 14.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                Text(
                  after?.toString() ?? '–',
                  style: AppText.cardTitle(size: 21, color: valueColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickedDetail extends StatelessWidget {
  final HeartMonthDay day;
  final int month;
  const _PickedDetail({required this.day, required this.month});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(18),
      ),
      // 글자 배율이 커지면 한 줄에 다 안 들어가므로 줄바꿈을 허락한다.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Text('$month월 ${day.day}일', style: AppText.cardTitle(size: 19)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '전 ${day.pair.before ?? '–'}',
                style: AppText.label(size: 18),
              ),
              const SizedBox(width: 10),
              const Text('→'),
              const SizedBox(width: 10),
              Text(
                '후 ${day.pair.after ?? '–'}',
                style: AppText.label(size: 18, color: AppColors.point),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
