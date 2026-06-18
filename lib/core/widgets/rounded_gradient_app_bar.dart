import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// 앱 전체 공용 상단바.
/// 핵심: 안쪽 콘텐츠를 [_contentHeight] 로 고정해서, 로고/아이콘이 있든
/// 제목만 있든 **모든 화면에서 높이가 100% 동일**하게 만든다.
/// (Scaffold 는 커스텀 상단바를 내용물 크기에 맞춰 그리기 때문에,
///  고정 높이 박스로 잠가주지 않으면 탭마다 길이가 달라진다.)
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

  // 상태바 아래 콘텐츠 영역 높이 (환자 홈의 로고/종 아이콘이 들어가는 크기)
  static const double _contentHeight = 40;
  static const double _topPad = 16;
  static const double _bottomPad = 18;

  @override
  Size get preferredSize =>
      const Size.fromHeight(_contentHeight + _topPad + _bottomPad);

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
          padding: const EdgeInsets.fromLTRB(20, _topPad, 20, _bottomPad),
          child: SizedBox(
            // ← 이 고정 높이가 핵심. 콘텐츠 유무와 상관없이 항상 동일.
            height: _contentHeight,
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
      ),
    );
  }
}
