import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_typography.dart';

/// 카드. **그림자를 쓰지 않는다** — 배경색([AppColors.bg]) 대비로 분리한다.
/// 강조가 필요한 카드만 3px 포인트/위험색 테두리를 두른다.
class SeniorCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;
  final double borderWidth;
  final double radius;
  final VoidCallback? onTap;

  const SeniorCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
    this.color = AppColors.surface,
    this.borderColor,
    this.borderWidth = 3,
    this.radius = 22,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: borderWidth),
      ),
      child: child,
    );

    if (onTap == null) return decorated;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: decorated,
      ),
    );
  }
}

/// 카드 안 구분선. 리스트 행 사이에만 쓴다.
class SeniorDivider extends StatelessWidget {
  const SeniorDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: AppColors.divider);
}

/// 라벨 행 앞의 작은 원 (● 지금 드실 약).
class Dot extends StatelessWidget {
  final double size;
  final Color color;
  const Dot({super.key, this.size = 10, this.color = AppColors.point});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 상태 배지 ("꼭 확인하세요", "정상이에요", "가장 쉬운 방법").
class SeniorBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final double radius;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const SeniorBadge({
    super.key,
    required this.label,
    this.background = AppColors.pointTint,
    this.foreground = AppColors.point,
    this.radius = 12,
    this.fontSize = 19,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        label,
        style: AppText.cardTitle(size: fontSize, color: foreground),
      ),
    );
  }
}

/// 설정·목록 행. 라벨 20px/700 + 값 18px/700 + `›`.
/// 행 높이는 패딩 17px 상하로 최소 56px를 넘긴다.
class SeniorListRow extends StatelessWidget {
  final String label;
  final String? value;
  final Color valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SeniorListRow({
    super.key,
    required this.label,
    this.value,
    this.valueColor = AppColors.textTertiary,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.label(size: 20, color: AppColors.textPrimary),
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  value!,
                  textAlign: TextAlign.right,
                  style: AppText.label(size: 18, color: valueColor),
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 56×32 토글. 스위치 단독으로 의미를 만들지 않고 항상 한글 설명과 함께 둔다.
class SeniorToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  const SeniorToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel = '켜기 끄기',
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Container(
          width: 56,
          height: 48,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 56,
            height: 32,
            padding: const EdgeInsets.all(3),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? AppColors.point : AppColors.strongBorder,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
