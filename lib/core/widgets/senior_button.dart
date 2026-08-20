import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_typography.dart';

/// 버튼 종류. 색은 눌러야 할 곳에만 쓴다 — [SeniorButtonKind.primary]와
/// [SeniorButtonKind.danger]만 색을 가지고, 나머지는 무채색이다.
enum SeniorButtonKind {
  /// 핵심 행동 (먹었어요, 등록하기). point 배경 + 흰 글자.
  primary,

  /// 위험 행동 (약국에 전화하기). danger 배경 + 흰 글자.
  danger,

  /// 보조 행동. bg 배경 + 진한 글자.
  secondary,

  /// 강조 보조 행동. headerBg 배경 + 2px 테두리.
  outline,

  /// 어두운 배경 위 보조 행동.
  dark,
}

/// 시니어 규격 버튼.
///
/// 높이는 [minHeight]로 **최소값만** 잡는다. 시스템 글자 크기가 커지면
/// 버튼이 세로로 자라야 하고, 글자가 잘리거나 화면 밖으로 밀리면 안 된다.
class SeniorButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final SeniorButtonKind kind;
  final double minHeight;
  final double fontSize;
  final double radius;

  const SeniorButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = SeniorButtonKind.primary,
    this.minHeight = 68,
    this.fontSize = 24,
    this.radius = 18,
  });

  @override
  State<SeniorButton> createState() => _SeniorButtonState();
}

class _SeniorButtonState extends State<SeniorButton> {
  bool _pressed = false;

  Color get _background {
    switch (widget.kind) {
      case SeniorButtonKind.primary:
        return _pressed ? AppColors.pointPressed : AppColors.point;
      case SeniorButtonKind.danger:
        return _pressed ? AppColors.dangerPressed : AppColors.danger;
      case SeniorButtonKind.secondary:
        return _pressed ? AppColors.chipBg : AppColors.bg;
      case SeniorButtonKind.outline:
        return _pressed ? AppColors.chipBg : AppColors.headerBg;
      case SeniorButtonKind.dark:
        return _pressed ? const Color(0xFF3A3A44) : AppColors.darkSurface;
    }
  }

  Color get _foreground {
    switch (widget.kind) {
      case SeniorButtonKind.primary:
      case SeniorButtonKind.danger:
        return Colors.white;
      case SeniorButtonKind.secondary:
      case SeniorButtonKind.outline:
        return AppColors.textBody;
      case SeniorButtonKind.dark:
        return AppColors.border;
    }
  }

  BoxBorder? get _border => widget.kind == SeniorButtonKind.outline
      ? Border.all(color: AppColors.strongBorder, width: 2)
      : null;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            width: double.infinity,
            // 고정 높이가 아니라 최소 높이 — 글자가 커지면 버튼이 자란다.
            constraints: BoxConstraints(minHeight: widget.minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _background,
              borderRadius: BorderRadius.circular(widget.radius),
              border: _border,
            ),
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: AppText.button(
                size: widget.fontSize,
                color: _foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 카드 하단의 텍스트 버튼 ("30분 뒤에 다시 알려주기", "다시 찍기").
/// 아이콘 없이 한글 라벨만 쓰고, 탭 영역은 48px 이상으로 잡는다.
class SeniorTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final double fontSize;

  /// 가로 전체를 차지할지. 카드 아래 단독으로 놓일 때는 true,
  /// 행 안에 다른 요소와 나란히 놓일 때는 false로 둔다
  /// (Row 안에서 무한 폭을 요구하면 레이아웃이 터진다).
  final bool expand;

  const SeniorTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.textTertiary,
    this.fontSize = 18,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: expand ? double.infinity : null,
          constraints: const BoxConstraints(minHeight: 48),
          // alignment를 주면 Container가 남은 폭을 다 차지해버린다.
          // 행 안에 놓일 때(expand:false)는 글자 폭만 쓰도록 비워둔다.
          alignment: expand ? Alignment.center : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.label(size: fontSize, color: color),
          ),
        ),
      ),
    );
  }
}
