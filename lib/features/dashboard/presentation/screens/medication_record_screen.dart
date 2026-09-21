import 'package:flutter/material.dart';
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
                // 오늘 하루를 시간대별로 한 장에 둔다. 날짜별 카드를 쌓는 대신
                // 달력이 날짜를 맡고, 여기서는 오늘 상태만 본다.
                DayDoseDetail(
                  dayLabel:
                      '${DateTime.now().month}월 ${DateTime.now().day}일 오늘',
                  doses: today.doses,
                  footnote: '날짜를 누르면 그날 결과가 여기에 나와요.',
                ),
                // 함께먹기 주의 화면은 로그인한 본인 약만 분석한다.
                if (patientId == null && interactionCount > 0) ...[
                  const SizedBox(height: 12),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 4,
                    ),
                    child: SeniorListRow(
                      label: '약 함께먹기 주의',
                      // 건수보다 무엇을 해야 하는지가 먼저다.
                      subtitle: '확인이 필요한 약이 있어요',
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
      // 아직 오지 않은 약 있는 날은 달성률에 넣지 않는다.
      if (record.date.year != now.year ||
          record.date.month != now.month ||
          !record.date.isBefore(now)) {
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
            final record = history[date];
            return _DayStatus(
              date: date,
              taken: 0,
              total: record?.total ?? 0,
              isFuture: true,
            );
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
  bool get partial => !isFuture && total > 0 && taken < total;

  /// 아직 오지 않은 약 있는 날. 먹었어요로 치지 않는다.
  bool get hasUpcomingSchedule => isFuture && total > 0;
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
              Expanded(child: Text('이번 달', style: AppText.cardTitle())),
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
    final names = missed
        .map((d) => '${_labels[d.date.weekday - 1]}요일')
        .join(', ');
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
          const SizedBox(height: 13),
          // 글자를 키우면 두 줄로 내려간다. 줄 밖으로 밀려나지 않게 Wrap을 쓴다.
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '✓',
                    style: AppText.cardTitle(size: 16, color: AppColors.point),
                  ),
                  const SizedBox(width: 6),
                  Text('다 드심', style: AppText.caption(size: 16)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '✗',
                    style: AppText.cardTitle(size: 16, color: AppColors.danger),
                  ),
                  const SizedBox(width: 6),
                  Text('못 드심', style: AppText.caption(size: 16)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '·',
                    style: AppText.cardTitle(size: 16, color: AppColors.point),
                  ),
                  const SizedBox(width: 6),
                  Text('약 있는 날', style: AppText.caption(size: 16)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
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
    } else if (status.hasUpcomingSchedule) {
      background = AppColors.pointTint;
      mark = Text(
        '·',
        style: AppText.cardTitle(size: 17, color: AppColors.point),
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
          '${status.hasUpcomingSchedule
              ? '약 있는 날'
              : status.future
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
