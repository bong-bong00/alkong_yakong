import 'package:flutter/material.dart';
import '../../../../core/polar_pharmacist_ui/constants/app_colors.dart';
import '../../../../core/polar_pharmacist_ui/theme/app_typography.dart';
import '../../../../core/polar_pharmacist_ui/widgets/senior_card.dart';
import '../../domain/heart_data.dart';

/// 저장된 심박 기록.
///
/// 한 줄에 글을 길게 늘어놓지 않는다 — 왼쪽에 언제·무엇을, 오른쪽에
/// 숫자를 세워 숫자만 눈으로 따라갈 수 있게 둔다.
class HeartReadingsCard extends StatelessWidget {
  final List<HeartReading> readings;
  final bool hasComparison;
  const HeartReadingsCard({
    super.key,
    required this.readings,
    required this.hasComparison,
  });

  /// "10월 2일" · "15:20" — 24시간 시계로 짧게.
  static String _day(DateTime at) => '${at.month}월 ${at.day}일';

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => SeniorCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('저장된 심박 기록', style: AppText.cardTitle(size: 21)),
        for (int i = 0; i < readings.length; i++) ...[
          if (i > 0)
            const Divider(height: 22, thickness: 1, color: AppColors.divider),
          if (i == 0) const SizedBox(height: 14),
          _ReadingRow(reading: readings[i]),
        ],
      ],
    ),
  );
}

class _ReadingRow extends StatelessWidget {
  final HeartReading reading;

  const _ReadingRow({required this.reading});

  @override
  Widget build(BuildContext context) {
    final at = reading.measuredAt.toLocal();
    return Semantics(
      label:
          '${HeartReadingsCard._day(at)} '
          '${HeartReadingsCard._clock(at)}, '
          '${reading.measurementContext.label}, ${reading.bpm}회',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${HeartReadingsCard._day(at)} '
                    '${HeartReadingsCard._clock(at)}',
                    style: AppText.cardTitle(size: 18),
                  ),
                  Text(
                    reading.measurementContext.label,
                    style: AppText.caption(
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('${reading.bpm}회/분', style: AppText.screenTitle(size: 22)),
          ],
        ),
      ),
    );
  }
}
