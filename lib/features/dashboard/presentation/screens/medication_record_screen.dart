import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medication/domain/medication_models.dart';
import 'patient_data.dart';

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

  /// 환자별 기록. null이면 본인의 오늘 상태를 쓴다.
  final List<DayRecord>? records;

  const MedicationRecordScreen({
    super.key,
    this.patientName,
    this.showBack = false,
    this.records,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(medicationProvider);
    final days = records;

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
                _MonthCard(rate: _monthRate(days)),
                const SizedBox(height: 12),
                _WeekCard(days: _weekStatuses(days, today)),
                const SizedBox(height: 12),
                _TodayCard(rows: _todayRows(days, today)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 데이터 정리 ───────────────────────────────────────────────
  // TODO: 백엔드 복약기록 API로 교체한다.

  int _monthRate(List<DayRecord>? days) {
    if (days == null || days.isEmpty) return 94;
    var taken = 0;
    var total = 0;
    for (final day in days) {
      total += day.slots.length;
      taken += day.slots.where((s) => s.taken).length;
    }
    if (total == 0) return 0;
    return (taken * 100 / total).round();
  }

  List<_DayStatus> _weekStatuses(List<DayRecord>? days, TodayMedication today) {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    if (days != null && days.isNotEmpty) {
      // 보호자 경로: 최근 기록을 이번 주에 오래된 순으로 채운다.
      final ordered = days.reversed.toList();
      return [
        for (int i = 0; i < 7; i++)
          if (i >= ordered.length)
            _DayStatus(date: monday.add(Duration(days: i)), taken: 0, total: 0)
          else
            _DayStatus(
              date: monday.add(Duration(days: i)),
              taken: ordered[i].slots.where((s) => s.taken).length,
              total: ordered[i].slots.length,
            ),
      ];
    }

    // 본인 경로: 지난 날은 데모, 오늘은 실제 상태, 앞날은 비운다.
    const demoTaken = <int>[3, 3, 2, 3, 3, 3, 3];
    return [
      for (int i = 0; i < 7; i++)
        () {
          final date = monday.add(Duration(days: i));
          final isToday = date.day == now.day && date.month == now.month;
          if (date.isAfter(DateTime(now.year, now.month, now.day))) {
            return _DayStatus(date: date, taken: 0, total: 0);
          }
          if (isToday) {
            return _DayStatus(
              date: date,
              taken: today.takenCount,
              total: today.doses.length,
              isToday: true,
            );
          }
          return _DayStatus(date: date, taken: demoTaken[i], total: 3);
        }(),
    ];
  }

  List<_RecordRow> _todayRows(List<DayRecord>? days, TodayMedication today) {
    if (days != null && days.isNotEmpty) {
      return [
        for (final slot in days.first.slots)
          _RecordRow(
            time: slot.label,
            medicines: slot.meds.join(' · '),
            taken: slot.taken,
          ),
      ];
    }
    return [
      for (final dose in today.doses)
        _RecordRow(
          time: dose.slot.spokenTime,
          medicines: dose.medicines.map((m) => m.ingredient).join(' · '),
          taken: dose.taken,
        ),
    ];
  }
}

class _DayStatus {
  final DateTime date;
  final int taken;
  final int total;
  final bool isToday;

  const _DayStatus({
    required this.date,
    required this.taken,
    required this.total,
    this.isToday = false,
  });

  bool get complete => total > 0 && taken == total;
  bool get future => total == 0;
  bool get partial => total > 0 && taken < total;
}

class _RecordRow {
  final String time;
  final String medicines;
  final bool taken;
  const _RecordRow({
    required this.time,
    required this.medicines,
    required this.taken,
  });
}

/// 카드 1 — 이번 달.
class _MonthCard extends StatelessWidget {
  final int rate;
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
                child: EmojiTitle(
                  emoji: '📊',
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
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('$rate%', style: AppText.hero(size: 40)),
              Text(
                rate >= 90 ? '잘 지키고 계세요' : '조금만 더 챙겨보세요',
                style: AppText.label(size: 18, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: rate / 100,
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
  const _WeekCard({required this.days});

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
          EmojiTitle(
            emoji: '📅',
            text: '이번 주',
            style: AppText.cardTitle(),
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
    } else if (status.future) {
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
          '${status.future ? '아직 오지 않은 날' : '${status.total}번 중 ${status.taken}번'}',
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

/// 카드 3 — 오늘 기록.
class _TodayCard extends StatelessWidget {
  final List<_RecordRow> rows;
  const _TodayCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EmojiTitle(
            emoji: '📝',
            text: '오늘 기록',
            style: AppText.cardTitle(),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 12),
              const SeniorDivider(),
              const SizedBox(height: 12),
            ],
            _TodayRow(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  final _RecordRow row;
  const _TodayRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 고정 폭을 주지 않는다 — 글자가 커져도 시각이 잘리면 안 된다.
        Text(
          row.time,
          softWrap: false,
          style: AppText.cardTitle(size: 19),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            row.medicines,
            style: AppText.body(size: 18.5, color: AppColors.textBody),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          row.taken ? '✓' : '대기',
          style: AppText.cardTitle(
            size: row.taken ? 20 : 17,
            color: row.taken ? AppColors.point : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
