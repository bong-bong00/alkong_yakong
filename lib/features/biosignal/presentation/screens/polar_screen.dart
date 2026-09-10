import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../domain/heart_data.dart';
import 'measure_screen.dart';

/// 25 · 폴라 센서.
///
/// 연결 상태를 한눈에 보여주고, **차는 방법 3단계**를 늘 같이 둔다.
/// 어르신이 센서를 못 차서 못 재는 경우가 실제로 가장 많다.
class PolarScreen extends StatefulWidget {
  final HeartData data;

  const PolarScreen({super.key, required this.data});

  @override
  State<PolarScreen> createState() => _PolarScreenState();
}

class _PolarScreenState extends State<PolarScreen> {
  late HeartData _data = widget.data;

  @override
  Widget build(BuildContext context) {
    final connected = _data.sensorConnected;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_data);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            SeniorBackHeader(
              title: '폴라 센서',
              onBack: () => Navigator.of(context).pop(_data),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusCard(connected: connected),
                    const SizedBox(height: 12),
                    if (connected) ...[
                      _InfoCard(data: _data),
                      const SizedBox(height: 16),
                      SeniorButton(
                        label: '지금 재기',
                        minHeight: 70,
                        fontSize: 24,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MeasureScreen(),
                          ),
                        ),
                      ),
                    ] else ...[
                      SeniorButton(
                        label: '기기 찾기',
                        icon: TablerIcons.bluetooth,
                        minHeight: 70,
                        fontSize: 24,
                        onPressed: _search,
                      ),
                    ],
                    const SizedBox(height: 12),
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('차는 방법', style: AppText.cardTitle(size: 20)),
                          const SizedBox(height: 14),
                          const NumberedSteps(
                            boxed: false,
                            steps: [
                              '띠 안쪽 두 군데를 물로 살짝 적셔주세요',
                              '가슴 아래, 명치 높이에 맞춰 차세요',
                              '약을 드시기 5분 전에 차 두시면 편해요',
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (connected) ...[
                      const SizedBox(height: 16),
                      SeniorButton(
                        label: '연결 끊기',
                        kind: SeniorButtonKind.dangerQuiet,
                        minHeight: 62,
                        fontSize: 20,
                        onPressed: () {
                          setState(
                            () => _data = _data.copyWith(sensorConnected: false),
                          );
                          showSeniorSnackbar(context, '센서 연결을 끊었어요');
                        },
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

  void _search() {
    // TODO: PolarService.findDeviceId 연동.
    setState(() => _data = _data.copyWith(sensorConnected: true));
    showSeniorSnackbar(context, '폴라 센서를 찾았어요');
  }
}

/// 큰 원 안의 하트 — 연결됐는지를 색으로 말한다.
class _StatusCard extends StatelessWidget {
  final bool connected;
  const _StatusCard({required this.connected});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          Container(
            width: 104,
            height: 104,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: connected ? AppColors.pointTint : AppColors.bg,
              shape: BoxShape.circle,
            ),
            child: ExcludeSemantics(
              child: Icon(
                TablerIcons.heart_filled,
                size: 56,
                color: connected ? AppColors.point : AppColors.strongLine,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            connected ? '폴라 센서가 연결됐어요' : '폴라 센서가 연결되지 않았어요',
            textAlign: TextAlign.center,
            style: AppText.emphasis(size: 25),
          ),
          const SizedBox(height: 8),
          Text(
            connected
                ? '가슴 띠를 차고 계시면 약 드신 뒤 심박수를 잽니다'
                : '가슴 띠를 차고 아래 버튼을 눌러주세요',
            textAlign: TextAlign.center,
            style: AppText.body(
              size: 18.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 기기 이름 · 배터리 · 마지막 측정.
class _InfoCard extends StatelessWidget {
  final HeartData data;
  const _InfoCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        children: [
          _InfoRow(label: '기기 이름', value: Text(
            'Polar H10',
            style: AppText.label(size: 18, color: AppColors.textPrimary),
          )),
          const SeniorDivider(),
          _InfoRow(
            label: '배터리',
            value: _BatteryGauge(percent: data.sensorBattery),
          ),
          const SeniorDivider(),
          _InfoRow(label: '마지막 측정', value: Text(
            data.sensorLastReadAt,
            style: AppText.label(size: 18, color: AppColors.textPrimary),
          )),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final Widget value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: LabelValueRow(
        label: Text(
          label,
          style: AppText.label(size: 19, color: AppColors.textSecondary),
        ),
        value: value,
      ),
    );
  }
}

/// 남은 배터리를 눈금 없이 채움으로만 보여준다.
class _BatteryGauge extends StatelessWidget {
  final int percent;
  const _BatteryGauge({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '배터리 $percent 퍼센트',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 20,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.point, width: 2),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: (percent / 100).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.point,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$percent%',
              style: AppText.label(size: 18, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
