import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../application/heart_sensor.dart';
import '../../domain/heart_data.dart';
import 'hr_alert_screen.dart';
import 'saved_screen.dart';

/// 27 / 28 · 심박수 재는 중 → 측정이 끝났어요.
///
/// 1분 동안 재고, 값은 폴라 센서에서 온다. 진행 막대는 흐르지 않고
/// 1초에 한 칸씩 찬다 — 한 칸씩 차는 쪽이 "지금 되고 있다"를 분명히 말한다.
class MeasureScreen extends StatefulWidget {
  final String guardianTitle;

  /// 센서 없이 화면만 볼 때 쓸 값. 테스트와 미리보기 전용이다.
  /// 실제 기기에서는 [sensor]가 준 값이 이긴다.
  final int result;

  /// 밖에서 넣어 주는 센서. 없으면 이 화면이 하나 만들어 쓴다.
  final HeartSensor? sensor;

  const MeasureScreen({
    super.key,
    this.guardianTitle = '딸 지안 님',
    this.result = 72,
    this.sensor,
  });

  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> {
  /// 1분을 잰다. 1초에 한 칸씩 찬다.
  static const Duration _tick = Duration(seconds: 1);
  static const int _totalSeconds = 60;

  /// 센서를 이 화면이 만들었으면 이 화면이 치운다.
  late final bool _ownsSensor = widget.sensor == null;
  late final HeartSensor _sensor = widget.sensor ?? HeartSensor();

  Timer? _timer;
  int _elapsed = 0;

  int get _progress => (_elapsed * 100 / _totalSeconds).round().clamp(0, 100);

  bool get _done => _elapsed >= _totalSeconds;

  /// 화면에 띄울 값. 센서가 아직 아무것도 못 줬으면 넘겨받은 값을 쓴다.
  int get _value => _sensor.bpm ?? widget.result;

  bool get _live => _sensor.status == HeartSensorStatus.streaming;

  /// 센서가 끊겼거나 붙지 못한 상태.
  bool get _lost =>
      _sensor.status == HeartSensorStatus.disconnected ||
      _sensor.status == HeartSensorStatus.failed;

  @override
  void initState() {
    super.initState();
    _sensor.addListener(_onSensor);
    if (_ownsSensor) unawaited(_sensor.start());
    _timer = Timer.periodic(_tick, (timer) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= _totalSeconds) timer.cancel();
    });
  }

  void _onSensor() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sensor.removeListener(_onSensor);
    // 보이지도 않는 화면이 센서를 잡고 있지 않도록.
    if (_ownsSensor) _sensor.dispose();
    super.dispose();
  }

  /// 남은 시간.
  int get _secondsLeft => (_totalSeconds - _elapsed).clamp(0, _totalSeconds);

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final fast = HeartPair.isFast(value);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorBackHeader(title: _done ? '측정이 끝났어요' : '심박수 재는 중'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MeasureCard(
                    progress: _progress,
                    // 재는 동안에도 센서가 주는 값을 그대로 보여 준다.
                    // 다 될 때까지 "–"만 보이면 되고 있는지 알 수 없다.
                    value: _done || _sensor.bpm != null ? value : null,
                    done: _done,
                    normal: _sensor.normal,
                  ),
                  const SizedBox(height: 12),
                  if (!_done) ...[
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '재는 동안 이렇게 해주세요',
                            style: AppText.cardTitle(size: 20),
                          ),
                          const SizedBox(height: 14),
                          const NumberedSteps(
                            boxed: false,
                            steps: [
                              '앉아서 가만히 계세요',
                              '숨을 편하게 쉬세요',
                              '가슴 띠는 그대로 두세요',
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 17,
                      ),
                      child: LabelValueRow(
                        label: Text(
                          _lost
                              ? '센서가 떨어졌어요'
                              : _live
                                  ? '폴라 베리티 센스로 재고 있어요'
                                  : '폴라 베리티 센스를 찾고 있어요',
                          style: AppText.cardTitle(
                            size: 19,
                            color: _lost
                                ? AppColors.danger
                                : AppColors.textPrimary,
                          ),
                        ),
                        value: Text(
                          _lost
                              ? '센서 단추를 한 번 눌러 주세요'
                              : '약 $_secondsLeft초 남았어요',
                          style: AppText.caption(size: 17.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SeniorButton(
                      label: '그만두기',
                      kind: SeniorButtonKind.secondary,
                      minHeight: 66,
                      fontSize: 21,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ] else ...[
                    _ResultCard(
                      value: value,
                      lowest: _sensor.lowest,
                      highest: _sensor.highest,
                      normal: _sensor.normal,
                    ),
                    const SizedBox(height: 16),
                    SeniorButton(
                      label: '기록 저장하기',
                      minHeight: 74,
                      fontSize: 24,
                      elevated: true,
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => fast
                              ? HrAlertScreen(
                                  bpm: value,
                                  guardianTitle: widget.guardianTitle,
                                )
                              : SavedScreen(
                                  bpm: value,
                                  guardianTitle: widget.guardianTitle,
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
    );
  }
}

/// 큰 원 + 진행 막대.
class _MeasureCard extends StatelessWidget {
  final int progress;
  final int? value;
  final bool done;
  final bool normal;

  const _MeasureCard({
    required this.progress,
    required this.value,
    required this.done,
    required this.normal,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        children: [
          _PulsingHeart(active: !done),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(
                value?.toString() ?? '–',
                style: AppText.hero(size: 64),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '회 / 분',
                  style: AppText.label(
                    size: 21,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: AppColors.bg,
                valueColor: const AlwaysStoppedAnimation(AppColors.point),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            // 정상이 아닐 때 "정상 범위예요"라고 말하지 않는다.
            done
                ? (normal ? '다 됐어요 · 정상 범위예요' : '다 됐어요 · 확인이 필요해요')
                : '재고 있어요 · 움직이지 마세요',
            textAlign: TextAlign.center,
            style: AppText.cardTitle(
              size: 20,
              color: done && !normal ? AppColors.danger : AppColors.point,
            ),
          ),
        ],
      ),
    );
  }
}

/// 132×132 원 안의 심장. 재는 동안만 천천히 뛴다.
class _PulsingHeart extends StatefulWidget {
  final bool active;
  const _PulsingHeart({required this.active});

  @override
  State<_PulsingHeart> createState() => _PulsingHeartState();
}

class _PulsingHeartState extends State<_PulsingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingHeart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 132,
        height: 132,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.pointTint,
          shape: BoxShape.circle,
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // 0% 크게·선명 → 50% 작게·흐리게. 시니어 화면이라 느리게 둔다.
            final t = Curves.easeInOut.transform(_controller.value);
            return Opacity(
              opacity: 1 - 0.65 * t,
              child: Transform.scale(scale: 1 - 0.28 * t, child: child),
            );
          },
          child: const Icon(
            TablerIcons.heartbeat,
            size: 64,
            color: AppColors.point,
          ),
        ),
      ),
    );
  }
}

/// 1분 동안 잰 결과 — 가장 낮게 / 가장 높게.
class _ResultCard extends StatelessWidget {
  final int value;

  /// 센서가 실제로 잰 값들에서 나온 최저·최고. 없으면 값 하나로 갈음한다.
  final int? lowest;
  final int? highest;
  final bool normal;

  const _ResultCard({
    required this.value,
    required this.lowest,
    required this.highest,
    required this.normal,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('1분 동안 잰 결과', style: AppText.cardTitle()),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MinMaxBox(label: '가장 낮게', value: lowest ?? value),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MinMaxBox(label: '가장 높게', value: highest ?? value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            normal
                ? '평소 재신 것과 비슷합니다. 걱정하실 것 없어요.'
                : '평소보다 빠릅니다. 앉아서 쉬신 뒤 한 번 더 재 보세요.',
            style: AppText.body(size: 18),
          ),
        ],
      ),
    );
  }
}

class _MinMaxBox extends StatelessWidget {
  final String label;
  final int value;

  const _MinMaxBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppText.label(size: 17.5)),
          const SizedBox(height: 4),
          Text('$value', style: AppText.cardTitle(size: 26)),
        ],
      ),
    );
  }
}
