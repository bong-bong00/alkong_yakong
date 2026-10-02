import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/senior_card.dart';

/// Adult resting reference labels; not a diagnosis or medication clearance.
String easyHeartRange(int bpm) => bpm < 60
    ? '느린 심박수'
    : bpm <= 100
    ? '정상 심박수'
    : '빠른 심박수';

String easyHeartChange(int before, int after) {
  final difference = after - before;
  if (difference == 0) return '복약 전과 같아요';
  return '복약 전보다 ${difference.abs()}회/분 ${difference > 0 ? '높아요' : '낮아요'}';
}

/// Keep Korean word endings together while still wrapping at spaces.
/// The original text remains available to assistive technology.
class _ResultText extends StatelessWidget {
  const _ResultText(this.text, {required this.style, this.align});
  final String text;
  final TextStyle style;
  final TextAlign? align;
  @override
  Widget build(BuildContext context) => Semantics(
    label: text,
    child: ExcludeSemantics(
      child: Text(
        text
            .split(' ')
            .map((word) => word.runes.map(String.fromCharCode).join('\u2060'))
            .join(' '),
        style: style,
        textAlign: align,
      ),
    ),
  );
}

class EasyHeartResult extends StatelessWidget {
  const EasyHeartResult({super.key, this.before, required this.value});
  final int? before;
  final int value;

  @override
  Widget build(BuildContext context) {
    final comparison = before != null;
    final scale = math.max(120, math.max(before ?? 0, value)).toDouble();
    return SeniorCard(
      radius: 26,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            comparison ? '복약 전후 심박수' : '복약 전 심박수',
            style: AppText.cardTitle(size: 21),
          ),
          const SizedBox(height: 14),
          if (comparison)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _bar(before!, '먹기 전', AppColors.textTertiary, scale),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.point,
                    size: 26,
                  ),
                ),
                Expanded(child: _bar(value, '먹은 후', AppColors.point, scale)),
              ],
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('$value', style: AppText.hero(size: 54)),
                  ),
                ),
                const SizedBox(width: 8),
                Text('회/분', style: AppText.label(size: 22)),
              ],
            ),
            const SizedBox(height: 8),
            _ResultText(
              easyHeartRange(value),
              align: TextAlign.center,
              style: AppText.label(size: 20, color: AppColors.point),
            ),
          ],
          if (comparison) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.pointRing,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('복약 전보다', style: AppText.caption(size: 17)),
                  const SizedBox(height: 3),
                  _ResultText(
                    before == value
                        ? '변화 없어요'
                        : '${(value - before!).abs()}회/분 ${value > before! ? '높아요' : '낮아요'}',
                    style: AppText.cardTitle(size: 24, color: AppColors.point),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _ResultText('정상 심박수: 60~100회/분', style: AppText.caption(size: 16)),
          const SizedBox(height: 4),
          _ResultText('성인이 쉴 때의 기준이에요.', style: AppText.caption(size: 16)),
          if (comparison) ...[
            const SizedBox(height: 10),
            _ResultText(
              '두 값만으로 약효나 부작용을 판단할 수는 없어요.',
              style: AppText.caption(size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bar(int bpm, String label, Color color, double scale) => Column(
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$bpm회/분',
          style: AppText.cardTitle(size: 24, color: color),
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 130,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 44,
            height: 130 * bpm / scale,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      _ResultText(label, style: AppText.label(size: 18, color: color)),
      _ResultText(easyHeartRange(bpm), style: AppText.caption(size: 16)),
    ],
  );
}

/// Code-native illustration of the arm band; no placeholder or remote asset.
class EasySensorWearIllustration extends StatelessWidget {
  const EasySensorWearIllustration({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        label: '손바닥이 보이는 팔의 팔꿈치 위쪽에 빨간 띠와 검은 폴라 센서를 착용한 그림',
        child: SizedBox(
          height: 165,
          child: CustomPaint(painter: _ArmBandPainter()),
        ),
      ),
      _ResultText(
        '팔꿈치 위에 착용',
        align: TextAlign.center,
        style: AppText.label(size: 18),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Semantics(
              label: '전원이 켜진 센서 뒷면의 초록빛 확대 그림',
              child: const SizedBox(
                width: 72,
                height: 72,
                child: CustomPaint(painter: _SensorBackPainter()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ResultText('센서 뒷면', style: AppText.label(size: 17)),
                  const SizedBox(height: 4),
                  _ResultText(
                    '초록빛이 나오는 면을 피부에 붙여 주세요.',
                    style: AppText.body(size: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ArmBandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Fixed illustration coordinates scale together, without stretching the sensor.
    final scale = math.min(size.width / 300, size.height / 165);
    canvas.save();
    canvas.translate((size.width - 300 * scale) / 2, 0);
    canvas.scale(scale);
    final arm = Path()
      ..moveTo(28, 12)
      ..quadraticBezierTo(54, 3, 82, 13)
      ..lineTo(91, 95)
      ..quadraticBezierTo(94, 103, 110, 104)
      ..lineTo(208, 102)
      // Palm and thumb identify the inner arm; the hand is not a rounded stump.
      ..quadraticBezierTo(220, 94, 229, 84)
      ..lineTo(242, 68)
      ..quadraticBezierTo(251, 60, 253, 69)
      ..quadraticBezierTo(255, 75, 242, 93)
      ..lineTo(283, 89)
      ..quadraticBezierTo(296, 88, 294, 97)
      ..quadraticBezierTo(294, 101, 284, 103)
      ..lineTo(252, 108)
      ..lineTo(289, 107)
      ..quadraticBezierTo(300, 108, 297, 116)
      ..quadraticBezierTo(296, 120, 287, 120)
      ..lineTo(254, 121)
      ..lineTo(284, 126)
      ..quadraticBezierTo(296, 127, 292, 135)
      ..quadraticBezierTo(290, 139, 281, 137)
      ..lineTo(250, 133)
      ..lineTo(273, 142)
      ..quadraticBezierTo(284, 146, 278, 152)
      ..quadraticBezierTo(274, 155, 266, 152)
      ..lineTo(236, 143)
      ..quadraticBezierTo(221, 140, 211, 136)
      ..lineTo(88, 150)
      ..quadraticBezierTo(38, 156, 33, 119)
      ..lineTo(22, 35)
      ..quadraticBezierTo(20, 18, 28, 12)
      ..close();
    canvas.drawPath(arm, Paint()..color = const Color(0xFFF3D5C4));
    canvas.drawPath(
      arm,
      Paint()
        ..color = const Color(0xFFD4AB95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Band is on the upper arm, above the elbow, not near the hand/wrist.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(25, 43, 90, 83),
        const Radius.circular(7),
      ),
      Paint()..color = const Color(0xFF963747),
    );
    canvas.drawLine(
      const Offset(35, 48),
      const Offset(35, 78),
      Paint()
        ..color = const Color(0xFF852B3A)
        ..strokeWidth = 2,
    );
    // Rectangular front on the palm-facing upper arm. Optical LEDs face the skin.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(44, 39, 82, 86),
        const Radius.circular(9),
      ),
      Paint()..color = const Color(0xFF202427),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(49, 54, 77, 70),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFF363C40),
    );
    final logo = TextPainter(
      text: const TextSpan(
        text: 'POLAR',
        style: TextStyle(
          color: Color(0xFFE8EBED),
          fontSize: 7,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    logo.paint(canvas, Offset(63 - logo.width / 2, 62 - logo.height / 2));
    final crease = Paint()
      ..color = const Color(0xFFD4AB95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(67, 114)
        ..quadraticBezierTo(73, 103, 85, 98),
      crease,
    );
    canvas.drawPath(
      Path()
        ..moveTo(214, 106)
        ..quadraticBezierTo(218, 117, 214, 130),
      crease,
    );
    canvas.drawPath(
      Path()
        ..moveTo(229, 107)
        ..quadraticBezierTo(238, 111, 242, 98),
      crease,
    );
    canvas.drawPath(
      Path()
        ..moveTo(231, 119)
        ..quadraticBezierTo(238, 122, 242, 136),
      crease,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SensorBackPainter extends CustomPainter {
  const _SensorBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF202427));
    canvas.drawCircle(
      center,
      radius * .74,
      Paint()..color = const Color(0xFF303A34),
    );
    canvas.drawCircle(
      center,
      radius * .60,
      Paint()..color = const Color(0x4435E879),
    );
    for (var index = 0; index < 6; index++) {
      final angle = index * math.pi / 3;
      final led =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius * .45);
      canvas.drawCircle(
        led,
        radius * .10,
        Paint()..color = const Color(0xFF57FF91),
      );
    }
    canvas.drawCircle(
      center,
      radius * .24,
      Paint()..color = const Color(0xFF17271D),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
