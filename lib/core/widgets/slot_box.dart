import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_typography.dart';

/// 때 한 칸 — 아침·점심·저녁.
///
/// 고치는 화면에서 고르는 칸과 약 자세히에서 읽는 칸이 같은 모양이다.
/// 같은 것을 두 모양으로 그리면 같은 것인 줄 모른다.
class SlotBox extends StatelessWidget {
  final String label;

  /// 고른 칸인지. 고른 칸은 파랑으로 채운다.
  final bool filled;

  /// 받은 자리를 다 채울지. 고르는 줄에서는 셋이 자리를 똑같이 나누고,
  /// 읽는 자리에서는 글자만큼만 차지한다.
  final bool expand;

  const SlotBox({
    super.key,
    required this.label,
    this.filled = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // alignment를 주면 Container가 받은 자리 끝까지 늘어난다. 읽는
      // 자리에서는 글자만큼만 차지해야 여럿이 한 줄에 선다. 키도 글자에
      // 맞춘다 — 최소 높이만 주면 글자가 칸 위쪽에 붙는다.
      constraints: expand ? const BoxConstraints(minHeight: 58) : null,
      alignment: expand ? Alignment.center : null,
      padding: expand
          ? const EdgeInsets.symmetric(horizontal: 18)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: filled ? AppColors.point : AppColors.secondaryFill,
        borderRadius: BorderRadius.circular(expand ? 14 : 12),
      ),
      child: Text(
        label,
        style: AppText.cardTitle(
          size: expand ? 19 : 17,
          color: filled ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }
}
