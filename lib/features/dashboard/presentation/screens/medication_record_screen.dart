import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/application/medication_controller.dart';
import '../../application/medication_calendar_provider.dart';
import '../../application/medication_history_provider.dart';
import '../widgets/day_dose_detail.dart';
import '../../../medication/domain/medication_models.dart';
import 'month_calendar_screen.dart';

/// 4c — 기록 탭.
///
/// 환자 본인과 보호자가 함께 쓴다.
/// 보호자 전용 색은 폐기했다 — 두 역할이 같은 파란 규칙을 쓴다.
///
/// 숫자는 크게, 설명은 말로. "복약률 94%"가 아니라
/// "잘 지키고 계세요 · 94%"로 읽힌다.
class MedicationRecordScreen extends ConsumerStatefulWidget {
  /// 보호자가 볼 때 환자 이름. 환자 본인은 null.
  final String? patientName;

  /// push로 열릴 때 true → B형 헤더(뒤로가기). 탭일 땐 A형.
  final bool showBack;

  /// 보호자가 볼 어르신 id. null이면 로그인한 본인의 기록이다.
  final String? patientUserId;

  /// 쉬운 화면에서 열렸을 때. 위에 이미 띄가 있어 제목을 더 위로 붙인다.
  final bool compactTop;

  /// 오늘 화면으로 돌아가는 길. 탭 루트일 때만 쓴다.
  final VoidCallback? onBackToToday;

  const MedicationRecordScreen({
    super.key,
    this.patientName,
    this.onBackToToday,
    this.showBack = false,
    this.patientUserId,
    this.compactTop = false,
  });

  @override
  ConsumerState<MedicationRecordScreen> createState() =>
      _MedicationRecordScreenState();
}

class _MedicationRecordScreenState
    extends ConsumerState<MedicationRecordScreen> {
  /// 한 주 칸에서 누른 날. 아무것도 안 눌렀으면 오늘이다.
  DateTime? _picked;

  /// 아래 칸이 보여줄 날.
  DateTime get _detailDate => _picked ?? dateOnly(DateTime.now());

  bool get _isToday => _detailDate == dateOnly(DateTime.now());

  /// 그 날의 아침·점심·저녁. 오늘은 지금 상태를, 지난 날은 달력 기록을 쓴다.
  List<DoseEntry> _detailDoses(TodayMedication today) {
    if (_isToday) return today.doses;
    final slots =
        ref
            .watch(
              medicationMonthSlotsProvider(
                MonthKey(
                  _detailDate.year,
                  _detailDate.month,
                  widget.patientUserId,
                ),
              ),
            )
            .valueOrNull?[_detailDate.day] ??
        const <String, bool>{};
    return [
      for (final slot in DoseSlot.values)
        if (slots.containsKey(slot.label))
          DoseEntry(
            slot: slot,
            medicines: const [],
            taken: slots[slot.label] == true,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final patientName = widget.patientName;
    final patientUserId = widget.patientUserId;
    final showBack = widget.showBack;
    final onBackToToday = widget.onBackToToday;
    final patientId = patientUserId;
    // 본인은 이 전화기의 오늘 상태를, 보호자는 서버에 올라온 어르신 기록을 쓴다.
    final today = patientId == null
        ? ref.watch(medicationProvider)
        : ref.watch(patientTodayProvider(patientId)).valueOrNull ??
              TodayMedication.empty;
    final loadedHistory =
        (patientId == null
                ? ref.watch(medicationHistoryProvider)
                : ref.watch(patientHistoryProvider(patientId)))
            .valueOrNull ??
        const <DateTime, DayAdherence>{};
    // 본인 기록만 OCR 직후 임시 날짜를 붙인다. 보호자 화면은 서버만 본다.
    final history = patientId == null
        ? mergeCachedScheduleDates(loadedHistory)
        : loadedHistory;

    final title = patientName == null ? '복약 기록' : '$patientName님 복약 기록';

    final heartCheck = _todayHeartCheck(today);

    return Container(
      color: AppColors.pageBg,
      // 제목이 본문에 있으므로 상태바를 여기서 피한다.
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (showBack)
              SeniorBackHeader(title: title)
            else
              // 시안은 제목을 머리띠가 아니라 본문 맨 위에 큼직하게 적는다.
              const SizedBox.shrink(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  widget.compactTop ? 2 : 20,
                  16,
                  28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!showBack) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: patientName == null
                                    ? '나의 '
                                    : '$patientName님 ',
                                style: AppText.screenTitle(
                                  size: 26,
                                ).copyWith(fontWeight: FontWeight.w500),
                              ),
                              TextSpan(
                                text: '복약 기록',
                                style: AppText.screenTitle(size: 28),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    // 간편 화면에는 탭이 없다. 거기서만 돌아가는 길을 낸다 —
                    // 탭이 있는 일반 화면에서는 시안대로 두지 않는다.
                    if (onBackToToday != null) ...[
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
                    AdherenceWeekCard(
                      days: weekAdherenceStatuses(today, history),
                      picked: _picked,
                      onOpenCalendar: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              MonthCalendarScreen(patientUserId: patientId),
                        ),
                      ),
                      // 화면을 옮기지 않는다 — 아래 칸만 그 날로 바뀐다.
                      onPickDay: (status) =>
                          setState(() => _picked = status.date),
                    ),
                    const SizedBox(height: 12),
                    // 오늘 하루를 시간대별로 한 장에 둔다. 날짜별 카드를 쌓는 대신
                    // 달력이 날짜를 맡고, 여기서는 오늘 상태만 본다.
                    DayDoseDetail(
                      dayLabel:
                          '${_detailDate.month}월 ${_detailDate.day}일'
                          '${_isToday ? ' 오늘' : ''}',
                      date: _detailDate,
                      doses: _detailDoses(today),
                      footnote: null,
                    ),
                    // 먹기 전과 후를 나란히 놓는 자리는 여기 하나다.
                    // 오늘 홈은 "지금 할 일" 한 가지만 말한다.
                    // 잰 값이 없어도 칸은 남긴다 — 여기서 심박수로 가는
                    // 길이 사라지면 어디로 가야 할지 알 수 없다.
                    const SizedBox(height: 12),
                    _TodayHeartCard(
                      check: heartCheck,
                      // push로 쌓아 연다 — go()로 바꿔치우면 뒤로가기가
                      // 돌아갈 자리를 잃어 앱이 꺼진다.
                      onTap: patientId == null
                          ? () => context.push('/biosignal')
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 오늘 심박수를 잰 시간대. 여러 번 쟀으면 가장 나중 것을 쓴다.
  static DoseHeartCheck? _todayHeartCheck(TodayMedication today) {
    DoseHeartCheck? found;
    for (final dose in today.doses) {
      if (dose.heartCheck != null) found = dose.heartCheck;
    }
    return found;
  }
}

/// 오늘 심박수 — 먹기 전과 후를 한 줄에 놓는다.
class _TodayHeartCard extends StatelessWidget {
  /// 오늘 잰 값. 없으면 null — 숫자를 채우지 않는다.
  final DoseHeartCheck? check;
  final VoidCallback? onTap;

  const _TodayHeartCard({required this.check, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            // 받은 화면은 동그라미가 아니라 모서리 둥근 네모다.
            decoration: BoxDecoration(
              color: AppColors.pointRing,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              TablerIcons.heart,
              size: 28,
              color: AppColors.point,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('오늘 심박수', style: AppText.cardTitle(size: 20)),
                const SizedBox(height: 2),
                if (check case final DoseHeartCheck reading)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '먹기 전 ',
                          style: AppText.label(
                            size: 17,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        TextSpan(
                          text: '${reading.before}',
                          style: AppText.cardTitle(size: 20),
                        ),
                        TextSpan(
                          text: ' → 후 ',
                          style: AppText.label(
                            size: 17,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        TextSpan(
                          text: '${reading.after}',
                          style: AppText.cardTitle(
                            size: 20,
                            color: AppColors.point,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    '오늘은 아직 측정하지 않았어요',
                    style: AppText.label(
                      size: 17,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (onTap != null) const SeniorChevron(),
        ],
      ),
    );
  }
}

// ── 데이터 정리 ───────────────────────────────────────────────
// 서버의 날짜별 기록 + 오늘 상태로 센다.

List<DayStatus> weekAdherenceStatuses(
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
          final record = history[date];
          return DayStatus(
            date: date,
            taken: 0,
            total: record?.total ?? 0,
            isFuture: true,
          );
        }
        if (date == todayDate) {
          return DayStatus(
            date: date,
            taken: today.takenCount,
            total: today.doses.length,
            isToday: true,
          );
        }
        final record = history[date];
        return DayStatus(
          date: date,
          taken: record?.taken ?? 0,
          total: record?.total ?? 0,
        );
      }(),
  ];
}

class DayStatus {
  final DateTime date;
  final int taken;
  final int total;
  final bool isToday;
  final bool isFuture;

  const DayStatus({
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
  bool get partial => !isFuture && total > 0 && taken < total;

  /// 아직 오지 않은 약 있는 날. 먹었어요로 치지 않는다.
  bool get hasUpcomingSchedule => isFuture && total > 0;
}

/// 카드 1 — 이번 달.
/// 카드 2 — 이번 주.
class AdherenceWeekCard extends StatelessWidget {
  final List<DayStatus> days;

  /// 한 주에서 한 달로 넓혀 보기.
  final VoidCallback onOpenCalendar;

  /// 날짜 하나를 눌렀을 때 — 아래 칸이 그 날로 바뀐다.
  final ValueChanged<DayStatus>? onPickDay;

  /// 지금 눌려 있는 날. 검은 테두리로 표시한다.
  final DateTime? picked;

  const AdherenceWeekCard({
    super.key,
    required this.days,
    required this.onOpenCalendar,
    this.onPickDay,
    this.picked,
  });

  static const List<String> _labels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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
                    label: Text('이번 주', style: AppText.cardTitle()),
                    value: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '달력 보기',
                            style: AppText.cardTitle(
                              size: 18,
                              color: AppColors.point,
                            ),
                          ),
                        ),
                        const Icon(
                          TablerIcons.chevron_right,
                          size: 24,
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
          // 일곱 칸이 폭을 고르게 나눠 갖는다. 칸을 고정 폭으로 두면
          // 작은 화면에서 마지막 요일이 줄 밖으로 밀려난다.
          Row(
            children: [
              for (int i = 0; i < days.length; i++)
                Expanded(
                  child: _WeekDay(
                    status: days[i],
                    label: _labels[i],
                    picked: picked == days[i].date,
                    onTap: onPickDay == null ? null : () => onPickDay!(days[i]),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {
  final DayStatus status;
  final String label;

  /// 지금 눌려 있는 날인지. 전체 달력과 같이 검은 테두리를 두른다.
  final bool picked;
  final VoidCallback? onTap;

  const _WeekDay({
    required this.status,
    required this.label,
    this.picked = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 명세서 43: 칸 안에는 날짜 숫자만 들어간다. 색이 상태를 말한다.
    late final Color background;
    late final Color ink;

    if (status.isToday) {
      background = AppColors.textPrimary;
      ink = Colors.white;
    } else if (status.future || status.noRecord) {
      background = AppColors.sunken;
      ink = AppColors.textTertiary;
    } else if (status.complete) {
      background = AppColors.calendarDone;
      ink = AppColors.pointBorder;
    } else {
      background = AppColors.calendarMissed;
      ink = AppColors.calendarMissedInk;
    }

    return Semantics(
      button: onTap != null,
      label:
          '${status.date.day}일 $label요일, '
          '${status.future
              ? '아직 오지 않은 날'
              : status.noRecord
              ? '기록 없음'
              : '${status.total}번 중 ${status.taken}번'}'
          '${onTap == null ? '' : ', 눌러서 그날 보기'}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: status.isToday
                  ? AppText.cardTitle(size: 16)
                  : AppText.label(
                      size: 16,
                      color: status.future
                          ? AppColors.chevron
                          : AppColors.textSecondary,
                    ),
            ),
            const SizedBox(height: 8),
            // 44가 제 크기지만, 좁은 화면에서는 받은 폭까지만 줄어든다.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 44, maxHeight: 44),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                    // 전체 달력과 같이, 누른 날은 검은 테두리로 짚는다.
                    border: picked
                        ? Border.all(color: AppColors.textPrimary, width: 2)
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${status.date.day}',
                      style: AppText.cardTitle(size: 19, color: ink),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 날짜 카드 한 장에 필요한 것.
