import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_typography.dart';
import 'senior_button.dart';
import 'senior_card.dart';

/// 화면 위에 동그라미를 쳐 가며 짚어 주는 안내 한 걸음.
class CoachMark {
  /// 짚을 자리. 그 위젯에 같은 열쇠를 달아 둔다.
  final GlobalKey target;

  final String title;
  final String body;

  /// 동그라미 대신 둥근 네모로 두를지. 가로로 긴 칸에 쓴다.
  final bool boxed;

  const CoachMark({
    required this.target,
    required this.title,
    required this.body,
    this.boxed = false,
  });
}

/// 화면 구성요소를 하나씩 동그라미 쳐 가며 설명한다.
///
/// 글로만 적은 도움말은 "그게 어디 있는데요"로 끝난다. 쓰시는 화면
/// 그대로를 덮고, 짚을 자리만 밝혀 둔 채 그 옆에 한 마디를 적는다.
///
/// 열어 둔 화면 위에 그대로 깔리므로, 여는 쪽에서 [show]를 쓴다.
class CoachMarks extends StatefulWidget {
  final List<CoachMark> marks;

  const CoachMarks({super.key, required this.marks});

  /// 지금 화면 위에 덮어 연다. 뒤 화면은 그대로 그려진 채로 남는다.
  static Future<void> show(BuildContext context, List<CoachMark> marks) {
    final shown = marks.where((mark) => _rectOf(mark.target) != null).toList();
    if (shown.isEmpty) return Future<void>.value();
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => CoachMarks(marks: shown),
      ),
    );
  }

  /// 그 위젯이 지금 화면 어디에 있는지. 안 그려져 있으면 null.
  static Rect? _rectOf(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  @override
  State<CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends State<CoachMarks> {
  int _at = 0;

  bool get _isLast => _at >= widget.marks.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _at += 1);
  }

  @override
  Widget build(BuildContext context) {
    final mark = widget.marks[_at];
    final rect = CoachMarks._rectOf(mark.target);
    if (rect == null) {
      // 짚을 자리가 사라졌으면 다음으로 넘긴다(빌드 중에는 못 바꾼다).
      WidgetsBinding.instance.addPostFrameCallback((_) => _next());
      return const SizedBox.shrink();
    }

    final screen = MediaQuery.sizeOf(context);
    // 동그라미는 칸보다 조금 크게 둘러 칸이 가려지지 않게 한다.
    final hole = rect.inflate(mark.boxed ? 8 : 10);
    final below = hole.bottom + 20;
    final putBelow = below + 220 < screen.height;

    return Semantics(
      container: true,
      label: '${mark.title}. ${mark.body}',
      child: ExcludeSemantics(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 바깥은 어둡게, 짚는 자리만 그대로 둔다. 아무 데나 누르면
              // 다음 걸음으로 간다 — 작은 단추를 찾게 하지 않는다.
              Positioned.fill(
                child: GestureDetector(
                  onTap: _next,
                  behavior: HitTestBehavior.opaque,
                  child: CustomPaint(
                    painter: _ScrimPainter(hole: hole, boxed: mark.boxed),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                top: putBelow ? below : null,
                bottom: putBelow ? null : screen.height - hole.top + 20,
                child: _Bubble(
                  step: _at + 1,
                  total: widget.marks.length,
                  title: mark.title,
                  body: mark.body,
                  isLast: _isLast,
                  onNext: _next,
                  onClose: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 짚는 자리만 남기고 덮는 그늘.
class _ScrimPainter extends CustomPainter {
  final Rect hole;
  final bool boxed;

  const _ScrimPainter({required this.hole, required this.boxed});

  @override
  void paint(Canvas canvas, Size size) {
    final cut = boxed
        ? (Path()..addRRect(
            RRect.fromRectAndRadius(hole, const Radius.circular(22)),
          ))
        : (Path()..addOval(
            Rect.fromCircle(
              center: hole.center,
              radius: math.max(hole.width, hole.height) / 2,
            ),
          ));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        cut,
      ),
      Paint()..color = AppColors.scrim,
    );
    canvas.drawPath(
      cut,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = AppColors.point,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.boxed != boxed;
}

/// 짚은 자리 옆에 붙는 설명 한 장.
class _Bubble extends StatelessWidget {
  final int step;
  final int total;
  final String title;
  final String body;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onClose;

  const _Bubble({
    required this.step,
    required this.total,
    required this.title,
    required this.body,
    required this.isLast,
    required this.onNext,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$step / $total',
            style: AppText.label(size: 16, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 6),
          Text(title, style: AppText.cardTitle(size: 22)),
          const SizedBox(height: 8),
          Text(body, style: AppText.body(size: 18.5)),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: SeniorButton(
                    label: '그만 보기',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 62,
                    fontSize: 19,
                    onPressed: onClose,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: SeniorButton(
                    label: isLast ? '다 봤어요' : '다음',
                    minHeight: 62,
                    fontSize: 21,
                    onPressed: onNext,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
