import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/domain/medication_models.dart';
import '../../application/heart_sensor.dart';

/// 4g — 심장 박동.
///
/// "생체신호 / 바이탈"이라는 말을 쓰지 않는다. 화면 이름은 심장 박동이고,
/// 동기화는 "최신 정보"다.
///
/// 다만 기기는 제품명 그대로 **폴라 베리티 센스**라고 부른다.
/// 돌려 말하면 어느 물건을 말하는지 알 수 없고, 사용설명서·구매처·
/// 가족과의 대화에서 쓰는 이름과도 어긋난다. 대신 처음 나오는 자리에는
/// 무엇인지 한 줄로 덧붙인다.
///
/// 연결이 끊기면 오류 화면 대신 5e 회복 패턴([RecoveryView])으로 바뀐다.
class HeartbeatScreen extends StatefulWidget {
  /// 함께 보고 있는 가족. "딸 지안 님".
  final String guardianTitle;

  const HeartbeatScreen({super.key, this.guardianTitle = '딸 지안 님'});

  @override
  State<HeartbeatScreen> createState() => _HeartbeatScreenState();
}

class _HeartbeatScreenState extends State<HeartbeatScreen> {
  /// 센서와 잇는 일은 전부 [HeartSensor]가 한다.
  /// 이 화면과 새 측정 화면이 같은 배선을 쓰도록, 여기서 다시 구현하지 않는다.
  final HeartSensor _sensor = HeartSensor();

  @override
  void initState() {
    super.initState();
    _sensor.addListener(_onSensor);
    unawaited(_sensor.start());
  }

  void _onSensor() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sensor.removeListener(_onSensor);
    _sensor.dispose();
    super.dispose();
  }

  Future<void> _connect() => _sensor.start();

  int? get _bpm => _sensor.bpm;
  List<int> get _samples => _sensor.samples;
  DateTime? get _lastReadAt => _sensor.lastReadAt;
  bool get _connecting => _sensor.status == HeartSensorStatus.connecting;
  bool get _disconnected =>
      _sensor.status == HeartSensorStatus.disconnected ||
      _sensor.status == HeartSensorStatus.failed;
  bool get _normal => _sensor.normal;

  bool _notifyGuardian = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '심장 박동'),
          Expanded(
            child: _disconnected ? _recovery() : _measuring(),
          ),
        ],
      ),
    );
  }

  // ── 5e 회복 화면 ──────────────────────────────────────────────
  Widget _recovery() {
    return RecoveryView(
      title: '지금은 심장 박동을\n재지 못하고 있어요',
      reassurance: '폴라 베리티 센스와 전화기가 떨어져 있어요. ',
      reassuranceEmphasis: '고장이 아니니 걱정하지 마세요.',
      steps: const [
        '센서가 팔이나 가슴에 잘 붙어 있는지 만져보세요',
        '센서 가운데 단추를 한 번 누르세요',
        '전화기를 센서 가까이 두세요',
      ],
      actionLabel: '다시 연결하기',
      onAction: _connect,
      stillWorksTitle: '약 알림은 그대로 와요',
      stillWorksBody: '센서가 끊겨도 복약 알림에는 영향이 없어요.',
      helperText: '그래도 안 되면\n${widget.guardianTitle}에게 도움 청하기',
      // 어르신 화면에서 밖으로 전화를 걸지 않는다. 연결이 끊겼다는
      // 사실만 가족에게 보내고, 전화는 받은 쪽이 건다.
      onCallHelper: () => showSeniorSnackbar(
        context,
        '${widget.guardianTitle}에게 연락이 갔어요',
      ),
      footnote: _lastReadAt == null
          ? null
          : '마지막으로 잰 시각 · 오늘 ${DoseSlot.absoluteTime(_lastReadAt!)}',
    );
  }

  // ── 재고 있는 상태 ────────────────────────────────────────────
  Widget _measuring() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SeniorCard(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Dot(size: 12),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _connecting ? '띠를 찾고 있어요' : '지금 재고 있어요',
                        style: AppText.label(size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Text(
                      _bpm?.toString() ?? '--',
                      style: AppText.hero(),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '회 / 분',
                        style: AppText.label(
                          size: 22,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SeniorBadge(
                  label: _normal ? '정상이에요' : '조금 빨라요',
                  background: _normal
                      ? AppColors.pointTint
                      : const Color(0xFFFAEFED),
                  foreground: _normal ? AppColors.point : AppColors.danger,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _TodayChart(samples: _samples),
          const SizedBox(height: 12),

          SeniorCard(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Row(
              children: [
                const Dot(size: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _connecting
                            ? '폴라 베리티 센스 찾는 중'
                            : '폴라 베리티 센스 연결됨',
                        style: AppText.cardTitle(size: 19),
                      ),
                      Text(
                        _lastReadAt == null
                            ? '팔이나 가슴에 차는 심박 센서예요'
                            : '${DoseSlot.absoluteTime(_lastReadAt!)} 최신 정보',
                        style: AppText.caption(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          SeniorCard(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '심장이 너무 빠르면\n${widget.guardianTitle}에게 바로 알려요',
                    style: AppText.label(
                      size: 19,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SeniorToggle(
                  value: _notifyGuardian,
                  semanticLabel: '가족에게 알리기',
                  onChanged: (v) => setState(() => _notifyGuardian = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          SeniorButton(
            label: '지금 다시 재기',
            minHeight: 66,
            fontSize: 23,
            onPressed: _connect,
          ),
        ],
      ),
    );
  }
}

/// 오늘 하루 막대 차트. 막대 10개, 과거는 회색, 지금만 포인트색.
class _TodayChart extends StatelessWidget {
  final List<int> samples;
  const _TodayChart({required this.samples});

  @override
  Widget build(BuildContext context) {
    final values = samples.isEmpty ? const <int>[] : samples;
    final min = values.isEmpty
        ? 0
        : values.reduce((a, b) => a < b ? a : b);
    final max = values.isEmpty
        ? 0
        : values.reduce((a, b) => a > b ? a : b);

    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('오늘 하루', style: AppText.cardTitle(size: 19)),
              ),
              Text(
                values.isEmpty ? '아직 없어요' : '$min ~ $max',
                style: AppText.label(size: 18, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 76,
            child: values.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '조금만 기다리시면 여기에 그려드려요',
                      style: AppText.caption(),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (int i = 0; i < values.length; i++) ...[
                        if (i > 0) const SizedBox(width: 5),
                        Expanded(
                          child: FractionallySizedBox(
                            heightFactor: max == min
                                ? 0.6
                                : (0.35 +
                                    0.65 *
                                        (values[i] - min) /
                                        (max - min)),
                            child: Container(
                              decoration: BoxDecoration(
                                color: i == values.length - 1
                                    ? AppColors.point
                                    : AppColors.chartPast,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final label in ['아침', '점심', '저녁', '지금'])
                Text(
                  label,
                  style: AppText.label(
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
