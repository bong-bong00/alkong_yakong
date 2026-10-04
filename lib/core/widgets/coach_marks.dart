import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_typography.dart';
import 'senior_button.dart';
import 'senior_card.dart';

/// 설명 한 장을 짚는 자리의 어느 쪽에 붙일지.
enum CoachPlacement {
  /// 위아래 중 넓은 쪽.
  auto,

  /// 짚는 자리 위.
  above,

  /// 짚는 자리 아래.
  below,
}

/// 화면 위에 동그라미를 쳐 가며 짚어 주는 안내 한 걸음.
class CoachMark {
  /// 짚을 자리. 그 위젯에 같은 열쇠를 달아 둔다.
  final GlobalKey target;

  final String title;
  final String body;

  /// 동그라미 대신 둥근 네모로 두를지. 가로로 긴 칸에 쓴다.
  final bool boxed;

  /// 둥근 네모의 모서리. 짚는 칸과 같게 둔다 — 자리를 칸에 꼭 맞춰
  /// 뚫으므로, 모서리가 다르면 귀퉁이에 그늘이나 틈이 남는다.
  final double radius;

  /// 칸 둘레로 더 밝히는 폭. 칸에 딱 붙여 뚫으면 칸 가장자리가 그늘에
  /// 먹혀 보이므로 조금은 남긴다. 뛰는 테처럼 칸 밖으로 움직이는 것이
  /// 있으면 그만큼 넓힌다.
  final double padding;

  /// 설명을 붙일 쪽.
  final CoachPlacement placement;

  const CoachMark({
    required this.target,
    required this.title,
    required this.body,
    this.boxed = false,
    this.radius = 22,
    this.padding = 6,
    this.placement = CoachPlacement.auto,
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  /// 마지막으로 움직인 쪽. 짚을 칸이 사라진 장을 건너뛸 때 같은 쪽으로
  /// 간다 — 앞으로 건너뛰면 "이전"을 눌러도 제자리로 돌아온다.
  bool _forward = true;

  void _next() {
    if (_isLast) {
      Navigator.of(context).maybePop();
      return;
    }
    _forward = true;
    setState(() => _at += 1);
    _reveal();
  }

  void _prev() {
    if (_at == 0) return;
    _forward = false;
    setState(() => _at -= 1);
    _reveal();
  }

  /// 짚을 칸이 화면 밖에 있거나 설명 붙일 쪽이 정해져 있으면 뒤 화면을
  /// 굴려 칸을 알맞은 자리로 옮긴 뒤 다시 잰다.
  Future<void> _reveal() async {
    final mark = widget.marks[_at];
    final target = mark.target.currentContext;
    if (target == null || Scrollable.maybeOf(target) == null) return;
    final rect = CoachMarks._rectOf(mark.target);
    if (rect == null) return;
    final screen = MediaQuery.sizeOf(context);
    final onScreen = rect.top >= 0 && rect.bottom <= screen.height;
    // 칸과 설명이 한 화면에 함께 들어갈 때만 굴려 자리를 낸다. 긴 목록을
    // 굴리면 칸의 머리가 화면 밖으로 밀려 정작 짚을 것이 안 보인다.
    final roomy = rect.height + _bubbleRoom < screen.height;
    final alignment = switch (mark.placement) {
      // 아래에 붙일 칸은 화면 위쪽으로, 위에 붙일 칸은 아래쪽으로 민다.
      CoachPlacement.below when roomy => 0.0,
      CoachPlacement.above when roomy => 1.0,
      _ => onScreen ? null : 0.5,
    };
    if (alignment == null) return;
    await Scrollable.ensureVisible(
      target,
      alignment: alignment,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mark = widget.marks[_at];
    final rect = CoachMarks._rectOf(mark.target);
    if (rect == null) {
      // 짚을 자리가 사라졌으면 가던 쪽으로 넘긴다(빌드 중에는 못 바꾼다).
      // 첫 장에서 뒤로 갈 데가 없으면 앞으로 간다.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _forward || _at == 0 ? _next() : _prev(),
      );
      return const SizedBox.shrink();
    }

    final screen = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    // 칸 둘레로 조금만 더 밝힌다. 너무 넓으면 칸 바깥 바탕이 테처럼
    // 남아 어디까지가 짚는 칸인지 흐려지고, 딱 붙이면 가장자리가 먹힌다.
    final hole = rect.inflate(mark.padding);
    final cut = _cutRect(hole, mark.boxed);

    // 설명은 실제로 밝힌 자리의 위아래 중 넓은 쪽에 붙인다. 칸 크기로
    // 재면 동그라미가 칸보다 클 때 설명이 동그라미를 덮거나 화면 밖으로
    // 잘린다.
    const gap = 20.0;
    final spaceBelow = screen.height - safe.bottom - cut.bottom - gap * 2;
    final spaceAbove = cut.top - safe.top - gap * 2;
    final putBelow = switch (mark.placement) {
      CoachPlacement.below => true,
      CoachPlacement.above => false,
      CoachPlacement.auto => spaceBelow >= spaceAbove,
    };
    // 고른 쪽이 설명 한 장이 들어갈 만큼 넉넉하지 않으면, 그쪽 화면 끝에
    // 붙여 짚는 자리에 살짝 겹쳐 띄운다. 짚는 자리가 조금 가려도 글이
    // 잘리는 것보다 낫고, 화면 끝에 붙이면 가리는 폭이 가장 작다.
    final fits = (putBelow ? spaceBelow : spaceAbove) >= _bubbleRoom;
    // 겹쳐 띄울 때는 화면 끝 여백을 줄여 짚는 자리를 덜 가린다.
    final top = putBelow && fits
        ? cut.bottom + gap
        : safe.top + (fits ? gap : 8);
    final bottom = !putBelow && fits
        ? screen.height - cut.top + gap
        : safe.bottom + gap;
    final alignment = putBelow == fits
        ? Alignment.topCenter
        : Alignment.bottomCenter;

    return Semantics(
      container: true,
      label: '${mark.title}. ${mark.body}',
      child: ExcludeSemantics(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 바깥은 어둡게, 짚는 자리만 그대로 둔다. 아무 데나 눌러서는
              // 넘어가지 않는다 — 읽다가 손이 닿아 장이 넘어가면 무엇을
              // 놓쳤는지 모른다. "다음"을 눌러야 넘어간다.
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  behavior: HitTestBehavior.opaque,
                  child: CustomPaint(
                    painter: _ScrimPainter(
                      hole: hole,
                      boxed: mark.boxed,
                      radius: mark.radius,
                      inflate: mark.padding,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                top: top,
                bottom: bottom,
                child: Align(
                  alignment: alignment,
                  // 글자 배율이 커서 자리보다 길어지면 잘리지 않고 밀린다.
                  child: SingleChildScrollView(
                    child: _Bubble(
                      step: _at + 1,
                      total: widget.marks.length,
                      title: mark.title,
                      body: mark.body,
                      isLast: _isLast,
                      onNext: _next,
                      onPrev: _prev,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 설명 한 장이 들어가는 데 드는 높이. 이보다 좁으면 겹쳐 띄운다.
const double _bubbleRoom = 260;

/// 그늘에서 실제로 뚫리는 자리.
///
/// 동그라미는 칸의 **짧은 변**에 맞춘다. 긴 변에 맞추면 가로로 넓은 칸
/// (예: 화면 폭 전체를 받는 큰 단추 자리)에서 동그라미가 칸보다 훨씬
/// 커져 위아래 칸까지 밝히고 설명 자리를 먹는다. 가로로 긴 칸은
/// [CoachMark.boxed]로 두른다.
Rect _cutRect(Rect hole, bool boxed) => boxed
    ? hole
    : Rect.fromCircle(
        center: hole.center,
        radius: math.min(hole.width, hole.height) / 2,
      );

/// 짚는 자리만 남기고 덮는 그늘.
class _ScrimPainter extends CustomPainter {
  final Rect hole;
  final bool boxed;
  final double radius;

  /// 칸 둘레로 넓힌 폭. 모서리도 그만큼 둥글게 해 칸과 나란히 둔다.
  final double inflate;

  const _ScrimPainter({
    required this.hole,
    required this.boxed,
    required this.radius,
    required this.inflate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cut = boxed
        ? (Path()..addRRect(
            RRect.fromRectAndRadius(hole, Radius.circular(radius + inflate)),
          ))
        : (Path()..addOval(_cutRect(hole, false)));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        cut,
      ),
      Paint()..color = AppColors.scrim,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole ||
      old.boxed != boxed ||
      old.radius != radius ||
      old.inflate != inflate;
}

/// 짚은 자리 옆에 붙는 설명 한 장.
class _Bubble extends StatelessWidget {
  final int step;
  final int total;
  final String title;
  final String body;
  final bool isLast;

  /// 첫 장인지. 돌아갈 장이 없으므로 "이전"을 두지 않는다.
  bool get isFirst => step == 1;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const _Bubble({
    required this.step,
    required this.total,
    required this.title,
    required this.body,
    required this.isLast,
    required this.onNext,
    required this.onPrev,
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
                // 첫 장에서는 돌아갈 데가 없다. 자리만 비워 두어 "다음"이
                // 어느 장에서나 같은 크기·같은 자리에 선다. 중간에 그만두려면
                // 뒤로 가기를 누르면 된다.
                Expanded(
                  flex: 2,
                  child: isFirst
                      ? const SizedBox.shrink()
                      : SeniorButton(
                          label: '이전',
                          kind: SeniorButtonKind.secondary,
                          minHeight: 62,
                          fontSize: 19,
                          onPressed: onPrev,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: SeniorButton(
                    label: isLast ? '알겠어요' : '다음',
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
