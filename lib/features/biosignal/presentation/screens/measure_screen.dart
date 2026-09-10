import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../domain/heart_data.dart';
import 'hr_alert_screen.dart';
import 'saved_screen.dart';

/// 27 / 28 · 심박수 재는 중 → 측정이 끝났어요.
///
/// 1분 동안 재는 것으로 하고, 진행은 **140ms마다 5%씩** 계단으로 올린다.
/// 부드럽게 흐르는 막대보다 한 칸씩 차는 쪽이 "지금 되고 있다"를 분명히 말한다.
class MeasureScreen extends StatefulWidget {
  final String guardianTitle;

  /// 재고 나서 나올 값. 실제로는 센서가 준다.
  final int result;

  const MeasureScreen({
    super.key,
    this.guardianTitle = '딸 지안 님',
    this.result = 72,
  });

  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> {
  static const Duration _tick = Duration(milliseconds: 140);
  static const int _stepPercent = 5;

  Timer? _timer;
  int _progress = 0;

  bool get _done => _progress >= 100;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (timer) {
      if (!mounted) return;
      setState(() => _progress = (_progress + _stepPercent).clamp(0, 100));
      if (_progress >= 100) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 남은 시간 — 계단 진행을 초로 되돌려 말해 준다.
  int get _secondsLeft {
    final remaining = (100 - _progress) / _stepPercent * _tick.inMilliseconds;
    return (remaining / 1000).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final fast = HeartPair.isFast(widget.result);
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
                    value: _done ? widget.result : null,
                    done: _done,
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
                          '폴라 센서로 재고 있어요',
                          style: AppText.cardTitle(size: 19),
                        ),
                        value: Text(
                          '약 $_secondsLeft초 남았어요',
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
                    _ResultCard(value: widget.result),
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
                                  bpm: widget.result,
                                  guardianTitle: widget.guardianTitle,
                                )
                              : SavedScreen(
                                  bpm: widget.result,
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

  const _MeasureCard({
    required this.progress,
    required this.value,
    required this.done,
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
            done ? '다 됐어요 · 정상 범위예요' : '재고 있어요 · 움직이지 마세요',
            textAlign: TextAlign.center,
            style: AppText.cardTitle(size: 20, color: AppColors.point),
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
  const _ResultCard({required this.value});

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
                child: _MinMaxBox(label: '가장 낮게', value: value - 4),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MinMaxBox(label: '가장 높게', value: value + 5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '평소 재신 것과 비슷합니다. 걱정하실 것 없어요.',
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
