import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../constants/app_colors.dart';
import '../theme/app_typography.dart';

/// 상단 바 (A형 · 탭 화면용).
///
/// 디자인의 가짜 상태바 행은 구현하지 않는다 — OS가 그리는 실제 상태바를
/// [SafeArea]로 피하고, 그 아래에 화면별 헤더 내용만 둔다.
/// 그라디언트 앱바는 폐기했다. 배경은 [AppColors.headerBg], 아래 1px 경계선.
class SeniorHeader extends StatelessWidget {
  final Widget child;

  /// 기본은 흰색. 심박수 이상 화면만 붉은 톤 헤더를 쓴다.
  final Color? background;
  final Color? borderColor;

  const SeniorHeader({
    super.key,
    required this.child,
    this.background,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background ?? AppColors.surface,
        border: Border(
          bottom: BorderSide(color: borderColor ?? AppColors.border, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          child: child,
        ),
      ),
    );
  }
}

/// 제목만 있는 A형 헤더 ("복약 기록", "내 정보", "알림").
class SeniorTitleHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SeniorTitleHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return SeniorHeader(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(title, style: AppText.screenTitle())),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// 상단 바 (B형 · 하위 화면). 뒤로가기 44×44 원형 + 제목 24px/900.
class SeniorBackHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  /// 카메라 화면처럼 어두운 배경 위에 얹을 때.
  final bool onDark;

  const SeniorBackHeader({
    super.key,
    required this.title,
    this.onBack,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        SeniorBackButton(onTap: onBack, onDark: onDark),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: AppText.screenTitle(
              size: 24,
              color: onDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );

    if (!onDark) return SeniorHeader(child: row);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
        child: row,
      ),
    );
  }
}

/// 뒤로 버튼. 56×56, 채움 + 2px 테두리.
///
/// 글자는 빼고 화살표만 둔다. 대신 **버튼처럼 보이는 모양은 유지한다** —
/// 테두리 없는 작은 `‹` 아이콘은 어르신이 버튼으로 인식하지 못한다.
/// [label]은 화면에 그리지 않고 스크린리더에만 읽힌다.
class SeniorBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool onDark;

  /// 스크린리더가 읽을 이름. 기본 "뒤로".
  final String label;

  const SeniorBackButton({
    super.key,
    this.onTap,
    this.onDark = false,
    this.label = '뒤로',
  });

  @override
  Widget build(BuildContext context) {
    // 쉘 안에 얹혀 돌아갈 곳이 없으면 그리지 않는다.
    if (onTap == null && !Navigator.of(context).canPop()) {
      return const SizedBox.shrink();
    }

    final fg = onDark ? Colors.white : AppColors.textBody;
    return Semantics(
      button: true,
      label: '$label 가기',
      child: GestureDetector(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onDark ? AppColors.camChip : AppColors.secondaryFill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: onDark ? AppColors.onDarkBorder : AppColors.strongLine,
              width: 2,
            ),
          ),
          child: ExcludeSemantics(
            child: Icon(TablerIcons.arrow_left, size: 28, color: fg),
          ),
        ),
      ),
    );
  }
}

/// 이름 첫 글자를 쓰는 원형 아바타. 이모지는 쓰지 않는다.
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color background;
  final Color foreground;

  const InitialAvatar({
    super.key,
    required this.name,
    this.size = 52,
    this.background = AppColors.surface,
    this.foreground = AppColors.inkGray,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '님' : trimmed.substring(0, 1);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        initial,
        style: AppText.cardTitle(size: size * 0.37, color: foreground),
      ),
    );
  }
}

/// 리스트 행 오른쪽의 `›`.
class SeniorChevron extends StatelessWidget {
  final Color color;
  const SeniorChevron({super.key, this.color = AppColors.chevron});

  @override
  Widget build(BuildContext context) {
    return Text('›', style: AppText.label(size: 22, color: color));
  }
}
