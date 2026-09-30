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
import '../../../dur_analysis/presentation/screens/dur_analysis_screen.dart';
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
    final interactionCount = today.interactionCount;

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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
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
                            text: patientName == null ? '나의 ' : '$patientName님 ',
                            style: AppText.screenTitle(
                              size: 26,
                            ).copyWith(fontWeight: FontWeight.w500),
                          ),
                          TextSpan(
                            text: '복약 기록',
                            style: AppText.screenTitle(size: 26),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                // 쉬운 화면에는 탭이 없다. 거기서만 돌아가는 길을 낸다 —
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
                  onOpenCalendar: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MonthCalendarScreen(patientUserId: patientId),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 오늘 하루를 시간대별로 한 장에 둔다. 날짜별 카드를 쌓는 대신
                // 달력이 날짜를 맡고, 여기서는 오늘 상태만 본다.
                DayDoseDetail(
                  dayLabel:
                      '${DateTime.now().month}월 ${DateTime.now().day}일 오늘',
                  doses: today.doses,
                  footnote: '날짜를 누르면 그날 결과가 여기에 나와요.',
                ),
                // 먹기 전과 후를 나란히 놓는 자리는 여기 하나다.
                // 오늘 홈은 "지금 할 일" 한 가지만 말한다.
                if (heartCheck != null) ...[
                  const SizedBox(height: 12),
                  _TodayHeartCard(
                    check: heartCheck,
                    onTap: patientId == null
                        ? () => context.go('/biosignal')
                        : null,
                  ),
                ],
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
                      // 건수보다 무엇을 해야 하는지가 먼저다.
                      subtitle: interactionCount > 0
                          ? '확인이 필요한 약이 있어요'
                          : '부딪히는 약은 없어요',
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
  final DoseHeartCheck check;
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
            decoration: const BoxDecoration(
              color: AppColors.pointTint,
              shape: BoxShape.circle,
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
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '먹기 전 ',
                        style: AppText.body(
                          size: 17,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      TextSpan(
                        text: '${check.before}',
                        style: AppText.cardTitle(size: 20),
                      ),
                      TextSpan(
                        text: ' → 후 ',
                        style: AppText.body(
                          size: 17,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      TextSpan(
                        text: '${check.after}',
                        style: AppText.cardTitle(
                          size: 20,
                          color: AppColors.point,
                        ),
                      ),
                    ],
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

  const AdherenceWeekCard({
    super.key,
    required this.days,
    required this.onOpenCalendar,
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
          // 일곱 칸이 폭을 고르게 나눠 갖는다. 칸을 고정 폭으로 두면
          // 작은 화면에서 마지막 요일이 줄 밖으로 밀려난다.
          Row(
            children: [
              for (int i = 0; i < days.length; i++)
                Expanded(
                  child: _WeekDay(status: days[i], label: _labels[i]),
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

  const _WeekDay({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    late final Color background;
    late final Widget mark;
    BoxBorder? border;

    if (status.isToday) {
      background = AppColors.point;
      // 오늘은 아직 끝나지 않았다. 다 드시면 ✓, 아니면 아무 표시도 하지
      // 않는다 — 먹은 횟수를 숫자로 적으면 0이 "빠뜨림"으로 읽힌다.
      mark = status.complete
          ? Text('✓', style: AppText.cardTitle(size: 17, color: Colors.white))
          : const SizedBox.shrink();
    } else if (status.future || status.noRecord) {
      background = AppColors.headerBg;
      mark = Text(
        '·',
        style: AppText.cardTitle(size: 17, color: AppColors.inactive),
      );
    } else if (status.complete) {
      background = AppColors.timelineRing;
      mark = Text(
        '✓',
        style: AppText.cardTitle(size: 17, color: AppColors.pointBorder),
      );
    } else {
      background = AppColors.surface;
      border = Border.all(color: AppColors.danger, width: 2);
      mark = Text(
        '✗',
        style: AppText.cardTitle(size: 17, color: AppColors.danger),
      );
    }

    return Semantics(
      label:
          '${status.date.day}일 $label요일, '
          '${status.future
              ? '아직 오지 않은 날'
              : status.noRecord
              ? '기록 없음'
              : '${status.total}번 중 ${status.taken}번'}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 38이 제 크기지만, 좁은 화면에서는 받은 폭까지만 줄어든다.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 38, maxHeight: 38),
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                  border: border,
                ),
                child: FittedBox(fit: BoxFit.scaleDown, child: mark),
              ),
            ),
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
