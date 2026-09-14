import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../application/medication_history_provider.dart';

/// 한 칸이 가질 수 있는 상태.
///
/// 칸 안에 복용 횟수를 적지 않는다 —
/// 숫자가 들어가면 한 달치를 한눈에 읽는 일이 다시 계산이 된다.
/// 약 일정이 없던 날은 [noRecord]다. 다 드신 날로 채우지 않는다.
enum DayMark { done, missed, today, future, noRecord }

/// 달력 한 칸.
@immutable
class CalendarDay {
  final int day;
  final DayMark mark;

  const CalendarDay(this.day, this.mark);
}

/// 빠뜨린 날 하나. 달력 아래에 **글로 다시** 적는다.
@immutable
class MissedDay {
  /// "8월 19일 수"
  final String label;

  /// "점심 약 한 번"
  final String detail;

  const MissedDay({required this.label, required this.detail});
}

/// 19 · 이번 달 달력.
///
/// 색은 세 가지뿐이다. 다 드신 날·빠뜨린 날·오늘.
/// 빠뜨린 날은 색만으로 끝내지 않고 아래에 글로 한 번 더 적는다 —
/// 색을 구분하기 어려운 눈에도 같은 사실이 남아야 한다.
///
/// 칸을 넘겨주지 않으면 내 복약 기록으로 이번 달을 그린다.
class MonthCalendarScreen extends ConsumerWidget {
  final int? month;
  final List<CalendarDay>? days;

  /// 달력 앞의 빈 칸 수. 1일이 무슨 요일인지에 따라 달라진다.
  final int? leadingBlanks;

  final List<MissedDay>? missed;

  /// 보호자가 볼 어르신 id. null이면 로그인한 본인의 기록이다.
  final String? patientUserId;

  const MonthCalendarScreen({
    super.key,
    this.month,
    this.days,
    this.leadingBlanks,
    this.missed,
    this.patientUserId,
  });

  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  static const List<String> _counts = ['한 번', '두 번', '세 번', '네 번'];

  static List<CalendarDay> _daysFrom(
    DateTime today,
    Map<DateTime, DayAdherence> history,
  ) {
    final daysInMonth = DateUtils.getDaysInMonth(today.year, today.month);
    return [
      for (int day = 1; day <= daysInMonth; day++)
        () {
          final date = DateTime(today.year, today.month, day);
          if (date == today) return CalendarDay(day, DayMark.today);
          if (date.isAfter(today)) return CalendarDay(day, DayMark.future);
          final record = history[date];
          if (record == null || record.total == 0) {
            return CalendarDay(day, DayMark.noRecord);
          }
          return CalendarDay(
            day,
            record.complete ? DayMark.done : DayMark.missed,
          );
        }(),
    ];
  }

  static List<MissedDay> _missedFrom(
    DateTime today,
    Map<DateTime, DayAdherence> history,
  ) {
    final records =
        history.values
            .where(
              (r) =>
                  r.date.isBefore(today) &&
                  r.date.month == today.month &&
                  r.date.year == today.year &&
                  r.total > 0 &&
                  !r.complete,
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return [
      for (final r in records)
        MissedDay(
          label:
              '${r.date.month}월 ${r.date.day}일 ${_weekdays[r.date.weekday - 1]}',
          detail:
              '${r.missedSlots.join('·')} 약 '
              '${_counts[(r.total - r.taken - 1).clamp(0, _counts.length - 1)]}',
        ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dateOnly(DateTime.now());
    final useHistory = days == null;
    final patientId = patientUserId;
    final AsyncValue<Map<DateTime, DayAdherence>> historyAsync = !useHistory
        ? const AsyncData(<DateTime, DayAdherence>{})
        : patientId == null
        ? ref.watch(medicationHistoryProvider)
        : ref.watch(patientHistoryProvider(patientId));
    final history = historyAsync.valueOrNull ?? const {};

    final shownMonth = month ?? today.month;
    final shownDays = days ?? _daysFrom(today, history);
    final blanks =
        leadingBlanks ?? DateTime(today.year, today.month).weekday - 1;
    final shownMissed = missed ?? _missedFrom(today, history);

    final doneCount = shownDays.where((d) => d.mark == DayMark.done).length;
    final recordedCount = shownDays
        .where((d) => d.mark == DayMark.done || d.mark == DayMark.missed)
        .length;
    final summary = historyAsync.isLoading
        ? '불러오는 중이에요'
        : recordedCount == 0
        ? '아직 쌓인 기록이 없어요'
        : '$recordedCount일 중 $doneCount일 다 드셨어요';

    // 앞 빈 칸까지 합쳐 7개씩 끊는다.
    final cells = <CalendarDay?>[
      for (int i = 0; i < blanks; i++) null,
      ...shownDays,
    ];
    final rowCount = (cells.length / 7).ceil();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorBackHeader(title: '$shownMonth월 달력'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LabelValueRow(
                          label: Text(
                            '$shownMonth월',
                            style: AppText.cardTitle(size: 21),
                          ),
                          value: Text(
                            summary,
                            style: AppText.label(
                              size: 17.5,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            for (final weekday in _weekdays)
                              Expanded(
                                child: Text(
                                  weekday,
                                  textAlign: TextAlign.center,
                                  style: AppText.cardTitle(
                                    size: 16,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (int row = 0; row < rowCount; row++) ...[
                          if (row > 0) const SizedBox(height: 6),
                          // 글자가 커지면 칸도 같이 커져야 한다. 높이를 박지
                          // 않고 가장 큰 칸에 줄을 맞춘다.
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (int col = 0; col < 7; col++) ...[
                                  if (col > 0) const SizedBox(width: 6),
                                  Expanded(
                                    child: row * 7 + col < cells.length &&
                                            cells[row * 7 + col] != null
                                        ? _DayCell(cells[row * 7 + col]!)
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const _Legend(),
                      ],
                    ),
                  ),
                  if (shownMissed.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _MissedCard(missed: shownMissed),
                  ],
                  const SizedBox(height: 16),
                  SeniorButton(
                    label: '복약 기록으로 돌아가기',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 62,
                    fontSize: 20,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final CalendarDay day;

  const _DayCell(this.day);

  @override
  Widget build(BuildContext context) {
    late final Color background;
    late final Color ink;
    late final String mark;
    late final String spoken;
    BoxBorder? border;

    switch (day.mark) {
      case DayMark.done:
        background = AppColors.pointTint;
        ink = AppColors.point;
        mark = '✓';
        spoken = '다 드신 날';
      case DayMark.missed:
        background = AppColors.dangerBg;
        ink = AppColors.danger;
        border = Border.all(color: AppColors.danger, width: 2);
        mark = '✕';
        spoken = '빠뜨린 날';
      case DayMark.today:
        background = AppColors.point;
        ink = Colors.white;
        border = Border.all(color: AppColors.pointBorder, width: 2);
        mark = '오늘';
        spoken = '오늘';
      case DayMark.future:
        background = AppColors.sunken;
        ink = AppColors.inactive;
        mark = '·';
        spoken = '아직 오지 않은 날';
      case DayMark.noRecord:
        background = AppColors.sunken;
        ink = AppColors.inactive;
        mark = '-';
        spoken = '기록 없는 날';
    }

    return Semantics(
      label: '${day.day}일 $spoken',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: border,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: AppText.cardTitle(size: 18, color: ink)
                    .copyWith(height: 1),
              ),
              const SizedBox(height: 2),
              Text(
                mark,
                textAlign: TextAlign.center,
                style: AppText.cardTitle(size: 15, color: ink)
                    .copyWith(height: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      children: [
        _LegendItem(
          color: AppColors.pointTint,
          border: null,
          label: '다 드신 날',
        ),
        _LegendItem(
          color: AppColors.dangerBg,
          border: Border.all(color: AppColors.danger, width: 2),
          label: '빠뜨린 날',
        ),
        _LegendItem(
          color: AppColors.point,
          border: Border.all(color: AppColors.pointBorder, width: 2),
          label: '오늘',
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final BoxBorder? border;
  final String label;

  const _LegendItem({
    required this.color,
    required this.border,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: border,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: AppText.label(size: 16.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// 빠뜨린 날을 글로 다시 적는다.
class _MissedCard extends StatelessWidget {
  final List<MissedDay> missed;

  const _MissedCard({required this.missed});

  /// 빠뜨린 때가 겹치면 그 사실을 짚어 준다.
  String get _hint {
    final slots = missed
        .map((m) => m.detail.split(' ').first)
        .toSet()
        .toList();
    if (missed.length < 2) {
      return '알림 소리를 더 크게 해 둘까요?';
    }
    return '두 번 다 ${slots.join('·')}이었어요. 알림 소리를 더 크게 해 둘까요?';
  }

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('빠뜨린 날', style: AppText.cardTitle(size: 20)),
          const SizedBox(height: 12),
          for (int i = 0; i < missed.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 12),
              const SeniorDivider(),
              const SizedBox(height: 12),
            ],
            LabelValueRow(
              label: Text(
                missed[i].label,
                style: AppText.cardTitle(size: 19, color: AppColors.danger),
              ),
              value: Text(
                missed[i].detail,
                style: AppText.body(size: 18.5, color: AppColors.textBody),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.sunken,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _hint,
              style: AppText.label(size: 18, color: AppColors.textBody),
            ),
          ),
        ],
      ),
    );
  }
}
