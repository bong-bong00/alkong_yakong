import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../domain/heart_data.dart';
import '../widgets/dumbbell_chart.dart';
import 'measure_screen.dart';
import 'monthly_heart_screen.dart';
import 'polar_screen.dart';

/// 24 · 심박수 관리.
///
/// **폴라 센서로 복약 전·후 두 번만 잰다.** 연속 선 그래프는 쓰지 않는다.
class HeartScreen extends StatefulWidget {
  final HeartData data;
  final String guardianTitle;

  const HeartScreen({
    super.key,
    this.data = HeartData.demo,
    this.guardianTitle = '딸 지안 님',
  });

  @override
  State<HeartScreen> createState() => _HeartScreenState();
}

class _HeartScreenState extends State<HeartScreen> {
  late HeartData _data = widget.data;

  @override
  Widget build(BuildContext context) {
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
                  index: 0,
                  onChanged: (i) {
                    if (i == 1) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MonthlyHeartScreen(
                            data: _data,
                            guardianTitle: widget.guardianTitle,
                          ),
                        ),
                      );
                    }
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
                  _TodayCard(data: _data),
                  const SizedBox(height: 12),
                  _WeekCard(data: _data),
                  const SizedBox(height: 12),
                  _SensorRow(
                    data: _data,
                    onTap: () async {
                      final updated = await Navigator.of(context).push<HeartData>(
                        MaterialPageRoute(
                          builder: (_) => PolarScreen(data: _data),
                        ),
                      );
                      if (updated != null && mounted) {
                        setState(() => _data = updated);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _NotifyRow(
                    guardianTitle: widget.guardianTitle,
                    value: _data.notifyGuardian,
                    onChanged: (v) =>
                        setState(() => _data = _data.copyWith(notifyGuardian: v)),
                  ),
                  const SizedBox(height: 16),
                  SeniorButton(
                    label: '지금 재기',
                    minHeight: 66,
                    fontSize: 23,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MeasureScreen(
                          guardianTitle: widget.guardianTitle,
                        ),
                      ),
                    ),
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

/// 오늘 잰 것 — 전·후 두 값을 나란히.
class _TodayCard extends StatelessWidget {
  final HeartData data;
  const _TodayCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final drop = data.today.drop;
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('오늘 잰 것', style: AppText.cardTitle())),
              Text(
                data.todaySlotLabel,
                style: AppText.label(size: 17, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ValueBox(
                  label: '약 먹기 전',
                  value: data.today.before,
                  background: AppColors.sunken,
                  labelColor: AppColors.textTertiary,
                  valueColor: AppColors.textPrimary,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: ExcludeSemantics(
                  child: Icon(
                    TablerIcons.arrow_right,
                    size: 30,
                    color: AppColors.point,
                  ),
                ),
              ),
              Expanded(
                child: _ValueBox(
                  label: '약 먹은 후',
                  value: data.today.after,
                  background: AppColors.pointTint,
                  labelColor: AppColors.point,
                  valueColor: AppColors.point,
                ),
              ),
            ],
          ),
          if (drop != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.sunken,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const ExcludeSemantics(
                    child: Icon(
                      TablerIcons.trending_down,
                      size: 24,
                      color: AppColors.point,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      drop > 0
                          ? '$drop회 낮아졌어요 · 정상 범위예요'
                          : '먹은 뒤에도 비슷해요 · 정상 범위예요',
                      style: AppText.label(
                        size: 18.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${data.beforeAt} · ${data.afterAt}에 쟀어요',
            style: AppText.caption(size: 17),
          ),
        ],
      ),
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String label;
  final int? value;
  final Color background;
  final Color labelColor;
  final Color valueColor;

  const _ValueBox({
    required this.label,
    required this.value,
    required this.background,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: value == null ? '$label 재지 못했어요' : '$label $value회',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppText.label(size: 17.5, color: labelColor)),
              const SizedBox(height: 6),
              Text(
                value?.toString() ?? '–',
                style: AppText.hero(size: 44, color: valueColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 이번 주 덤벨 막대.
class _WeekCard extends StatelessWidget {
  final HeartData data;
  const _WeekCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('이번 주', style: AppText.cardTitle())),
              const DumbbellLegend(),
            ],
          ),
          const SizedBox(height: 16),
          DumbbellChart(days: data.week),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.sunken,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              data.allDropped
                  ? '7일 모두 약을 드신 뒤에 낮아졌어요'
                  : '며칠은 약을 드신 뒤에도 비슷했어요',
              style: AppText.label(size: 18, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 센서 상태 한 줄.
class _SensorRow extends StatelessWidget {
  final HeartData data;
  final VoidCallback onTap;

  const _SensorRow({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final connected = data.sensorConnected;
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // 점은 제목 줄 높이에 맞춘다. 가운데 정렬하면 두 줄 사이에 낀다.
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: connected ? AppColors.point : AppColors.strongLine,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? '폴라 센서 연결됨' : '폴라 센서 끊김',
                  style: AppText.cardTitle(size: 19),
                ),
                Text(
                  connected
                      ? '배터리 ${data.sensorBattery}% · '
                          '${data.sensorLastReadAt}에 잰 것이 마지막이에요'
                      : '가슴 띠를 차고 다시 연결해 주세요',
                  style: AppText.caption(size: 17.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: SeniorChevron(),
          ),
        ],
      ),
    );
  }
}

/// 심박수가 빠르면 보호자에게 자동으로 알리는 스위치.
class _NotifyRow extends StatelessWidget {
  final String guardianTitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotifyRow({
    required this.guardianTitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '심박수가 너무 빠르면\n$guardianTitle에게 바로 알려요',
              style: AppText.label(size: 19, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          SeniorToggle(
            value: value,
            semanticLabel: '심박수가 빠를 때 $guardianTitle에게 알리기',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
