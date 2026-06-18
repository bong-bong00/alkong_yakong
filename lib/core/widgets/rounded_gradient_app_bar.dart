import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// 앱 전체에서 쓰는 단 하나의 상단바.
/// 모든 화면이 이 위젯을 쓰므로 높이(104)가 물리적으로 동일하게 통일된다.
/// - [color] 로 환자(kPrimary) / 보호자(kGuardian) 색만 구분
/// - [leading] 로 좌측 로고 등, [actions] 로 우측 아이콘 배치
class RoundedGradientAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final Color color;
  final Widget? leading;
  final List<Widget> actions;

  const RoundedGradientAppBar(
    this.title, {
    super.key,
    this.color = kPrimary,
    this.leading,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(104);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
