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
  Widget build(BuildContext context) => Semantics(
    label: '팔꿈치 위쪽 팔에 센서 밴드를 착용한 그림',
    child: SizedBox(
      height: 150,
      child: CustomPaint(painter: _ArmBandPainter()),
    ),
  );
}

class _ArmBandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final arm = Paint()..color = AppColors.pointRing;
    final left = size.width * .25;
    final right = size.width * .75;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, 28, right, 120),
        const Radius.circular(35),
      ),
      arm,
    );
    canvas.drawLine(
      Offset(size.width * .65, 30),
      Offset(size.width * .65, 118),
      Paint()
        ..color = AppColors.textTertiary
        ..strokeWidth = 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(size.width * .39, 22, size.width * .52, 126),
        const Radius.circular(12),
      ),
      Paint()..color = AppColors.point,
    );
    canvas.drawCircle(
      Offset(size.width * .455, 72),
      23,
      Paint()..color = AppColors.textPrimary,
    );
    canvas.drawCircle(
      Offset(size.width * .455, 72),
      12,
      Paint()..color = AppColors.surface,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
