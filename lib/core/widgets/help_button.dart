import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../constants/app_colors.dart';
import 'senior_card.dart';

/// 머리띠 오른쪽의 도움말 단추 — 동그란 "i".
///
/// 글자를 달지 않는다. 날짜와 이름이 있는 줄에서 글자 단추는 자리를
/// 많이 먹고, 글자 배율을 키우면 이름을 밀어낸다. 동그라미 하나는
/// 배율이 커져도 자리가 그대로다.
///
/// 흰 면에 그림자로 띄운다 — 다른 화면의 단추와 같은 손짓이다.
class HelpButton extends StatelessWidget {
  final VoidCallback onTap;

  /// 한 변 길이. 손가락이 닿아야 하므로 48 아래로 내리지 않는다.
  final double size;

  const HelpButton({super.key, required this.onTap, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '도움말',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              boxShadow: kCardShadow,
            ),
            child: Icon(
              TablerIcons.info_circle,
              size: size * 0.55,
              color: AppColors.point,
            ),
          ),
        ),
      ),
    );
  }
}
