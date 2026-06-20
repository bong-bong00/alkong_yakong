import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// 실시간 심박 모니터링 화면 (흐르는 애니메이션 버전).
/// 보호자 현황 탭의 "현재 심박" 카드를 누르면 진입.
///
/// ▸ 지금은 데모: 1초마다 새 심박값이 들어오고, 그래프는 매 프레임 다시 그려
///   왼쪽으로 매끄럽게 흐른다(응급실 모니터 느낌).
/// ▸ 실제 연동: 팀원의 biosignalProvider(BiosignalState)를 watch 하도록
///   _demoTick() 부분만 교체. 필드명(currentHr, currentRmssd, isMoving,
///   isAnomalyDetected, isAnalyzing, aiReport)을 그대로 맞춰뒀다.
///
/// 부담 최소화: 최근 _maxPoints 개만 메모리에 유지하고, 화면을 벗어나면
/// dispose()에서 타이머·애니메이션을 정리해 배터리/리소스 낭비를 막는다.
/// 위치: lib/features/dashboard/presentation/screens/biosignal_live_screen.dart
class BiosignalLiveScreen extends StatefulWidget {
  final Color accent;
  final String? patientName; // 보호자가 볼 때 환자 이름. 환자 본인은 null.
  final int baseHr; // 환자별 평상시 기준 심박

  const BiosignalLiveScreen({
    super.key,
    this.accent = kGuardian,
    this.patientName,
    this.baseHr = 76,
  });

  @override
  State<BiosignalLiveScreen> createState() => _BiosignalLiveScreenState();
}

class _BiosignalLiveScreenState extends State<BiosignalLiveScreen>
    with SingleTickerProviderStateMixin {
  static const int _maxPoints = 60; // 그래프에 유지할 최근 심박 개수
  static const Duration _interval = Duration(seconds: 1); // 새 값 주기
  static const Color _danger = Color(0xFFE24B4A);

  // ── BiosignalState 와 1:1 대응되는 데모 상태 ──
  int _currentHr = 78;
  double _currentRmssd = 42.0;
  bool _isMoving = false;
  bool _isAnomalyDetected = false;
  // ignore: unused_field  (연동 시 사용: AI 분석 중 표시)
  final bool _isAnalyzing = false;
  // ignore: unused_field  (연동 시 사용: AI 분석 리포트)
  final String _aiReport = '';

  // 흐름 구현용: 값 리스트 + 직전 값(보간으로 부드럽게 흐르게)
  final List<double> _hr = [];
  double _prevHr = 78;
  Timer? _timer;
  late final AnimationController _anim; // 매 프레임 다시 그리기 + 흐름 진행도(0~1)
  final _rand = Random();

  @override
  void initState() {
    super.initState();
    _currentHr = widget.baseHr;
    for (int i = 0; i < _maxPoints; i++) {
      _hr.add((widget.baseHr - 2 + _rand.nextInt(6)).toDouble());
    }
    _prevHr = _hr.last;

    // 매 프레임 화면을 다시 그려 라인이 흐르게 한다. 주기(_interval)에 맞춰 0→1 반복.
    _anim = AnimationController(vsync: this, duration: _interval)..repeat();

    _timer = Timer.periodic(_interval, (_) => _demoTick());
  }

  @override
  void dispose() {
    _timer?.cancel(); // 화면 벗어나면 데이터 갱신 중단
    _anim.dispose(); // 애니메이션 정리 (배터리/리소스 절약)
    super.dispose();
  }

  // 데모용: 새 심박값 한 개를 만들어 리스트에 넣는다.
  void _demoTick() {
    final last = _hr.isEmpty ? 78.0 : _hr.last;
    double next = last + (_rand.nextInt(7) - 3); // -3 ~ +3
    if (_rand.nextInt(100) < 8) next += 20 + _rand.nextInt(15); // 가끔 빈맥
    next = next.clamp(58, 140);

    setState(() {
      _prevHr = _hr.isEmpty ? next : _hr.last;
      _hr.add(next);
      if (_hr.length > _maxPoints + 1) _hr.removeAt(0);

      _currentHr = next.round();
      _currentRmssd = (35 + _rand.nextInt(20)).toDouble();
      _isMoving = _rand.nextInt(100) < 15;
      _isAnomalyDetected = !_isMoving && next > 100;
    });
    _anim.forward(from: 0); // 새 값마다 흐름 0부터 다시
  }

  bool get _normal => !_isAnomalyDetected;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final Color hrColor = _isAnomalyDetected ? _danger : accent;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '실시간 심박',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            // ── 현재 심박 큰 숫자 ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 26),
              decoration: BoxDecoration(
                color: hrColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: hrColor.withValues(alpha: 0.20)),
              ),
              child: Column(
                children: [
                  Text(
                    widget.patientName == null
                        ? '지금'
                        : '${widget.patientName}님 · 지금',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text('💓', style: TextStyle(fontSize: 30)),
                      const SizedBox(width: 8),
                      Text(
                        '$_currentHr',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w900,
                          color: hrColor,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'bpm',
                        style: TextStyle(fontSize: 18, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _statusChip(),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 흐르는 실시간 그래프 ──
            Row(
              children: [
                const Text(
                  '실시간 추이',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: kText,
                  ),
                ),
                const SizedBox(width: 8),
                _LiveDot(color: _normal ? accent : _danger),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: _card(),
              child: SizedBox(
                height: 190,
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size.infinite,
                      painter: _FlowPainter(
                        values: _hr,
                        progress: _anim.value, // 0~1, 한 칸 흐름 진행도
                        lineColor: hrColor,
                        minY: 50,
                        maxY: 150,
                        bandLow: 60,
                        bandHigh: 100,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(child: _legend(const Color(0xFFEAF7F1), '정상 범위 (60~100)')),
            const SizedBox(height: 18),

            // ── 보조 지표 ──
            Row(
              children: [
                _metric(
                  'HRV (RMSSD)',
                  _currentRmssd.toStringAsFixed(0),
                  'ms',
                  accent,
                ),
                const SizedBox(width: 12),
                _metric(
                  '상태',
                  _isMoving ? '움직임 중' : '안정',
                  '',
                  _isMoving ? const Color(0xFFE6A100) : accent,
                ),
              ],
            ),
            const SizedBox(height: 18),

            if (_isAnomalyDetected) _anomalyCard(),
          ],
        ),
      ),
    );
  }

  Widget _statusChip() {
    final Color c = _isAnomalyDetected ? _danger : const Color(0xFF2E7D32);
    final String label = _isAnomalyDetected
        ? '심박 이상 감지'
        : (_isMoving ? '활동 중 · 정상' : '안정 · 정상');
    final IconData icon = _isAnomalyDetected
        ? Icons.warning_amber_rounded
        : Icons.check_circle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Widget _anomalyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _danger.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: _danger, size: 20),
              SizedBox(width: 8),
              Text(
                '심박 이상 감지',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: kText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '안정 상태에서 심박이 분당 100회를 넘었어요. '
            '잠시 지켜보고, 계속되면 환자에게 연락해보세요.',
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, String unit, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(
                    unit,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
      ],
    );
  }
}

/// 라인을 한 칸씩 왼쪽으로 흐르게 그리는 페인터.
/// progress(0~1)만큼 왼쪽으로 이동시켜 새 값이 오른쪽에서 부드럽게 들어온다.
class _FlowPainter extends CustomPainter {
  final List<double> values;
  final double progress;
  final Color lineColor;
  final double minY, maxY, bandLow, bandHigh;

  _FlowPainter({
    required this.values,
    required this.progress,
    required this.lineColor,
    required this.minY,
    required this.maxY,
    required this.bandLow,
    required this.bandHigh,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final w = size.width;
    final h = size.height;

    // 화면에 보이는 점 개수 (마지막 한 칸은 흐름으로 들어오는 중)
    final int visible = values.length - 1;
    final double step = w / (visible - 1);

    double yFor(double v) =>
        h - ((v - minY) / (maxY - minY)).clamp(0.0, 1.0) * h;
    // i번째 점의 x. progress만큼 왼쪽으로 당겨 흐르게.
    double xFor(int i) => (i - progress) * step;

    // 정상 범위 밴드
    final band = Paint()..color = const Color(0xFFEAF7F1);
    canvas.drawRect(Rect.fromLTRB(0, yFor(bandHigh), w, yFor(bandLow)), band);

    // 가로 보조선
    final grid = Paint()
      ..color = const Color(0xFFEDEDED)
      ..strokeWidth = 1;
    for (final v in [75.0, 100.0, 125.0]) {
      final y = yFor(v);
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }

    // 라인 path (오른쪽 끝은 다음 값으로 보간되어 들어옴)
    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = xFor(i);
      final y = yFor(values[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // 라인 아래 채움
    final lastX = xFor(values.length - 1);
    final fill = Path.from(path)
      ..lineTo(lastX, h)
      ..lineTo(xFor(0), h)
      ..close();
    canvas.drawPath(fill, Paint()..color = lineColor.withValues(alpha: 0.10));

    // 라인
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 현재 지점 점 (오른쪽 가장자리 근처, 직전 값 위치)
    final cx = xFor(values.length - 2);
    final cy = yFor(values[values.length - 2]);
    if (cx <= w + 4) {
      canvas.drawCircle(Offset(cx, cy), 4.5, Paint()..color = lineColor);
      canvas.drawCircle(
        Offset(cx, cy),
        4.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) =>
      old.progress != progress ||
      old.values != values ||
      old.lineColor != lineColor;
}

BoxDecoration _card() => BoxDecoration(
  color: kCard,
  borderRadius: BorderRadius.circular(18),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ],
);

/// 깜빡이는 라이브 표시 점
class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}
