import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_typography.dart';

/// 바텀시트 공통 셸.
///
/// 중복 복용 차단, 처방 리필, 센서 착용 확인, 로그아웃, 쉬운 모드 메뉴,
/// 건너뛰기 확인, 돌보는 분 추가가 모두 이 셸을 쓴다.
///
/// 버튼은 **주 → 보조 → 취소** 순서로 세로로 쌓는다.
class SeniorSheet extends StatelessWidget {
  /// 27/900 제목. 시트가 무엇을 묻는지 한 문장으로.
  final String title;

  /// 19/500 본문. 강조할 말은 [SeniorSheetBody]로 굵게 만든다.
  final Widget? body;

  /// 주 → 보조 → 취소 순으로 넣는다.
  final List<Widget> actions;

  /// 제목 위에 들어가는 내용 (기록 증거 박스, 그리드 등).
  final Widget? leading;

  const SeniorSheet({
    super.key,
    required this.title,
    this.body,
    this.actions = const [],
    this.leading,
  });

  /// 스크림을 눌러 닫을 수 있는 표준 방식으로 띄운다.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool dismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      barrierColor: AppColors.scrim,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Color(0x2E14161E),
            blurRadius: 40,
            offset: Offset(0, -12),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 52,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDDDE6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (leading != null) ...[leading!, const SizedBox(height: 14)],
              Text(title, style: AppText.emphasis(size: 27)),
              if (body != null) ...[const SizedBox(height: 14), body!],
              for (final action in actions) ...[
                const SizedBox(height: 14),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 시트 본문. 강조할 말만 굵고 진하게 둔다.
class SeniorSheetBody extends StatelessWidget {
  /// 일반 문장과 강조 문장을 번갈아 넣는다. 홀수 번째가 강조다.
  final List<String> parts;

  const SeniorSheetBody(this.parts, {super.key});

  /// 강조 없이 한 문장만 둘 때.
  SeniorSheetBody.plain(String text, {super.key}) : parts = [text];

  @override
  Widget build(BuildContext context) {
    final base = AppText.body(size: 19, color: AppColors.textBody);
    return Text.rich(
      TextSpan(
        children: [
          for (int i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: i.isOdd
                  ? AppText.body(
                      size: 19,
                      color: AppColors.textPrimary,
                      weight: FontWeight.w900,
                    )
                  : base,
            ),
        ],
      ),
      style: base,
    );
  }
}
