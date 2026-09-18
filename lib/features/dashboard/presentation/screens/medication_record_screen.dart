import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../../core/widgets/senior_timeline.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../dur_analysis/presentation/screens/dur_analysis_screen.dart';
import '../../application/medication_history_provider.dart';
import '../../../medication/domain/medication_models.dart';
import 'month_calendar_screen.dart';

/// 4c — 기록 탭.
///
/// 환자 본인과 보호자가 함께 쓴다.
/// 보호자 전용 색은 폐기했다 — 두 역할이 같은 파란 규칙을 쓴다.
///
/// 숫자는 크게, 설명은 말로. "복약률 94%"가 아니라
/// "잘 지키고 계세요 · 94%"로 읽힌다.
class MedicationRecordScreen extends ConsumerWidget {
  /// 보호자가 볼 때 환자 이름. 환자 본인은 null.
  final String? patientName;

  /// push로 열릴 때 true → B형 헤더(뒤로가기). 탭일 땐 A형.
  final bool showBack;

  /// 보호자가 볼 어르신 id. null이면 로그인한 본인의 기록이다.
  final String? patientUserId;

  /// 오늘 화면으로 돌아가는 길. 탭 루트일 때만 쓴다.
  final VoidCallback? onBackToToday;

  const MedicationRecordScreen({
    super.key,
    this.patientName,
    this.onBackToToday,
    this.showBack = false,
    this.patientUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientId = patientUserId;
    // 본인은 이 전화기의 오늘 상태를, 보호자는 서버에 올라온 어르신 기록을 쓴다.
    final today = patientId == null
        ? ref.watch(medicationProvider)
        : ref.watch(patientTodayProvider(patientId)).valueOrNull ??
              TodayMedication.empty;
    final history =
        (patientId == null
                ? ref.watch(medicationHistoryProvider)
                : ref.watch(patientHistoryProvider(patientId)))
            .valueOrNull ??
        const <DateTime, DayAdherence>{};
    final interactionCount = today.interactionCount;

    final title = patientName == null ? '복약 기록' : '$patientName님 복약 기록';

    return Column(
      children: [
        if (showBack)
          SeniorBackHeader(title: title)
        else
          SeniorTitleHeader(title: title),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 기록에서 홈으로 돌아가는 길이 탭바뿐이면 길을 잃는다.
                if (patientId == null && onBackToToday != null) ...[
                  SeniorButton(
                    label: '오늘 화면으로 돌아가기',
                    icon: TablerIcons.calendar_event,
                    minHeight: 72,
                    fontSize: 23,
                    elevated: true,
                    onPressed: onBackToToday,
                  ),
                  const SizedBox(height: 12),
                ],
                _MonthCard(rate: _monthRate(today, history)),
                const SizedBox(height: 12),
                _WeekCard(
                  days: _weekStatuses(today, history),
                  onOpenCalendar: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MonthCalendarScreen(patientUserId: patientId),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 날짜를 위에서 아래로, 최신이 위다. 오늘 카드가 축 위의 "지금".
                ..._dayTimeline(context, today, history),
                // 함께먹기 주의 화면은 로그인한 본인 약만 분석한다.
                if (patientId == null) ...[
                const SizedBox(height: 12),
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 4,
                  ),
                  child: SeniorListRow(
                    label: '약 함께먹기 주의',
                    icon: TablerIcons.alert_triangle,
                    iconColor: interactionCount > 0
                        ? AppColors.danger
                        : AppColors.textTertiary,
                    value: interactionCount > 0 ? '$interactionCount건' : '없어요',
                    valueColor: interactionCount > 0
                        ? AppColors.danger
                        : AppColors.textTertiary,
                    trailing: const SeniorChevron(),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DurAnalysisScreen(),
                      ),
                    ),
                  ),
                ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 데이터 정리 ───────────────────────────────────────────────
  // 서버의 날짜별 기록 + 오늘 상태로 센다.

  /// 기록이 하나도 없으면 null. 없는 기록을 퍼센트로 지어내지 않는다.
  int? _monthRate(TodayMedication today, Map<DateTime, DayAdherence> history) {
    var taken = 0;
    var total = 0;
    final now = dateOnly(DateTime.now());
    for (final record in history.values) {
      if (record.date.year != now.year ||
          record.date.month != now.month ||
          record.date == now) {
        continue;
      }
      taken += record.taken;
      total += record.total;
    }
    final live = todayAdherence(today);
    taken += live.taken;
    total += live.total;
    if (total == 0) return null;
    return (taken * 100 / total).round();
  }

  List<_DayStatus> _weekStatuses(
    TodayMedication today,
    Map<DateTime, DayAdherence> history,
  ) {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    // 지난 날은 서버 기록, 오늘은 오늘 상태, 앞날은 비운다.
    final todayDate = dateOnly(now);
    return [
      for (int i = 0; i < 7; i++)
        () {
          final date = monday.add(Duration(days: i));
          if (date.isAfter(todayDate)) {
            return _DayStatus(date: date, taken: 0, total: 0, isFuture: true);
          }
          if (date == todayDate) {
            return _DayStatus(
              date: date,
              taken: today.takenCount,
              total: today.doses.length,
              isToday: true,
            );
          }
          final record = history[date];
          return _DayStatus(
            date: date,
            taken: record?.taken ?? 0,
            total: record?.total ?? 0,
          );
        }(),
    ];
  }

  /// 날짜 카드를 시간 축으로 쌓는다. 최신이 위, 오늘이 축 위의 "지금".
  ///
  /// 기록이 없는 날은 만들지 않는다 — "다 드셨다"로도 "빠뜨렸다"로도
  /// 채우지 않는다.
  List<Widget> _dayTimeline(
    BuildContext context,
    TodayMedication today,
    Map<DateTime, DayAdherence> history,
  ) {
    final now = DateTime.now();
    final todayKey = dateOnly(now);

    final days = history.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    // 오늘은 서버 기록보다 이 전화기의 상태가 정확하다.
    final entries = <_DayCardData>[
      if (today.doses.isNotEmpty)
        _DayCardData(
          date: todayKey,
          taken: today.takenCount,
          total: today.doses.length,
          missedSlots: [
            for (final dose in today.doses)
              if (!dose.taken && dose.slot.todayAt(now).isBefore(now))
                dose.slot.label,
          ],
          heartCheck: today.doses
              .map((d) => d.heartCheck)
              .whereType<DoseHeartCheck>()
              .firstOrNull,
          isToday: true,
        ),
      for (final day in days)
        if (dateOnly(day.date) != todayKey)
          _DayCardData(
            date: day.date,
            taken: day.taken,
            total: day.total,
            missedSlots: day.missedSlots,
            heartCheck: null,
            isToday: false,
          ),
    ];

    if (entries.isEmpty) return const [];

    final rows = <Widget>[];
    for (int i = 0; i < entries.length; i++) {
      rows.add(
        TimelineRow(
          current: entries[i].isToday,
          past: !entries[i].isToday,
          last: i == entries.length - 1,
          child: _DayCard(
            data: entries[i],
            onTap: entries[i].isToday ? onBackToToday : null,
          ),
        ),
      );
      if (i != entries.length - 1) rows.add(kTimelineGap);
    }
    return rows;
  }

}

class _DayStatus {
  final DateTime date;
  final int taken;
  final int total;
  final bool isToday;
  final bool isFuture;

  const _DayStatus({
    required this.date,
    required this.taken,
    required this.total,
    this.isToday = false,
    this.isFuture = false,
  });

  bool get complete => total > 0 && taken == total;
  bool get future => isFuture;

  /// 지난 날인데 약 일정이 없었던 날. 다 드신 날로도 빠뜨린 날로도 치지 않는다.
  bool get noRecord => !isFuture && !isToday && total == 0;
  bool get partial => total > 0 && taken < total;
}

/// 카드 1 — 이번 달.
class _MonthCard extends StatelessWidget {
  /// 기록이 없으면 null.
  final int? rate;
  const _MonthCard({required this.rate});

  @override
  Widget build(BuildContext context) {
    final month = DateTime.now().month;
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: IconTitle(
                  icon: TablerIcons.chart_bar,
                  text: '이번 달',
                  style: AppText.cardTitle(),
                ),
              ),
              Text(
                '$month월',
                style: AppText.cardTitle(size: 19, color: AppColors.point),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rate == null)
            Text(
              '아직 쌓인 기록이 없어요',
              style: AppText.label(size: 18, color: AppColors.textTertiary),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('$rate%', style: AppText.hero(size: 40)),
                Text(
                  rate! >= 90 ? '잘 지키고 계세요' : '조금만 더 챙겨보세요',
                  style: AppText.label(size: 18, color: AppColors.textTertiary),
                ),
              ],
            ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (rate ?? 0) / 100,
              minHeight: 12,
              backgroundColor: AppColors.divider,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.point),
            ),
          ),
        ],
      ),
    );
  }
}

/// 카드 2 — 이번 주.
class _WeekCard extends StatelessWidget {
  final List<_DayStatus> days;

  /// 한 주에서 한 달로 넓혀 보기.
  final VoidCallback onOpenCalendar;

  const _WeekCard({required this.days, required this.onOpenCalendar});

  static const List<String> _labels = ['월', '화', '수', '목', '금', '토', '일'];

  String get _summary {
    final missed = days.where((d) => d.partial && !d.isToday).toList();
    if (missed.isEmpty) return '이번 주는 빠뜨린 약이 없어요.';
    final names = missed.map((d) => '${_labels[d.date.weekday - 1]}요일').join(', ');
    return '$names 약을 한 번 못 드셨어요.';
  }

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: '이번 주 · 달력으로 보기',
            child: GestureDetector(
              onTap: onOpenCalendar,
              behavior: HitTestBehavior.opaque,
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  // 글자가 커지면 "달력으로 보기"가 제목 아래로 내려간다.
                  child: LabelValueRow(
                    label: IconTitle(
                      icon: TablerIcons.calendar,
                      text: '이번 주',
                      style: AppText.cardTitle(),
                    ),
                    value: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '달력으로 보기',
                            style: AppText.cardTitle(
                              size: 17.5,
                              color: AppColors.point,
                            ),
                          ),
                        ),
                        const Icon(
                          TablerIcons.chevron_right,
                          size: 26,
                          color: AppColors.point,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < days.length; i++)
                _WeekDay(status: days[i], label: _labels[i]),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            _summary,
            style: AppText.caption(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {
  final _DayStatus status;
  final String label;

  const _WeekDay({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    late final Color background;
    late final Widget mark;
    BoxBorder? border;

    if (status.isToday) {
      background = AppColors.point;
      mark = Text(
        status.complete ? '✓' : '${status.taken}',
        style: AppText.cardTitle(size: 17, color: Colors.white),
      );
    } else if (status.future || status.noRecord) {
      background = AppColors.headerBg;
      mark = Text(
        '·',
        style: AppText.cardTitle(size: 17, color: AppColors.inactive),
      );
    } else if (status.complete) {
      background = AppColors.pointTint;
      mark = Text(
        '✓',
        style: AppText.cardTitle(size: 17, color: AppColors.point),
      );
    } else {
      background = AppColors.bg;
      border = Border.all(color: AppColors.strongBorder, width: 2);
      mark = Text(
        '${status.taken}',
        style: AppText.cardTitle(size: 17, color: AppColors.textTertiary),
      );
    }

    return Semantics(
      label: '${status.date.day}일 $label요일, '
          '${status.future ? '아직 오지 않은 날' : status.noRecord ? '기록 없음' : '${status.total}번 중 ${status.taken}번'}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: border,
            ),
            child: mark,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: status.isToday
                ? AppText.cardTitle(size: 16, color: AppColors.point)
                : AppText.label(size: 16, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 날짜 카드 한 장에 필요한 것.
class _DayCardData {
  final DateTime date;
  final int taken;
  final int total;
  final List<String> missedSlots;

  /// 그날 잰 심박수. 없으면 줄을 빼고 간격도 줄인다.
  final DoseHeartCheck? heartCheck;

  final bool isToday;

  const _DayCardData({
    required this.date,
    required this.taken,
    required this.total,
    required this.missedSlots,
    required this.heartCheck,
    required this.isToday,
  });

  bool get complete => total > 0 && taken >= total;

  /// 지난 날인데 다 못 드셨으면 빠뜨린 날이다.
  bool get missed => !isToday && !complete;

  String get label {
    final base = '${date.month}월 ${date.day}일';
    return isToday ? '$base 오늘' : base;
  }

  /// "다 드셨어요" / "점심 놓침" / "아직 안 드셨어요"
  String get status {
    if (complete) return '다 드셨어요';
    if (missedSlots.isNotEmpty) return '${missedSlots.join(' · ')} 놓침';
    return isToday ? '아직 안 드셨어요' : '${total - taken}번 놓침';
  }
}

/// 하루 한 장. 막대 개수가 그날 복용 횟수고, 칠해진 만큼 드신 것이다.
class _DayCard extends StatelessWidget {
  final _DayCardData data;
  final VoidCallback? onTap;

  const _DayCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final check = data.heartCheck;
    return SeniorCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      onTap: onTap,
      borderColor: data.isToday
          ? AppColors.point
          : data.missed
              ? AppColors.dangerBorder
              : null,
      borderWidth: data.isToday ? 3 : 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabelValueRow(
            label: Text(data.label, style: AppText.cardTitle(size: 21)),
            value: Text(
              data.status,
              style: AppText.cardTitle(
                size: 18,
                // 놓친 날만 붉게. 화면당 위험색은 하나다.
                color: data.missed ? AppColors.danger : AppColors.point,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < data.total; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                Expanded(
                  child: Container(
                    height: 13,
                    decoration: BoxDecoration(
                      color: i < data.taken
                          ? AppColors.point
                          : AppColors.strongBorder,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // 안 잰 날에는 이 줄을 아예 두지 않는다.
          if (check != null) ...[
            const SizedBox(height: 12),
            Text(
              '심박수 ${check.before} → ${check.after}',
              style: AppText.caption(size: 17.5),
            ),
          ],
        ],
      ),
    );
  }
}
