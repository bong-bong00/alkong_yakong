import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// 알콩약콩 시니어 리디자인 타이포그래피.
///
/// **16px이 하한이다.** 그보다 작은 텍스트는 만들지 않는다.
/// 16px 이하가 필요하다고 느껴지면 그 정보는 삭제 대상이다.
///
/// weight는 400 / 500 / 700 / 900만 쓴다.
///
/// **굵기는 아껴 쓴다.** 900은 화면에서 가장 먼저 읽혀야 하는 것에만
/// 붙인다 — 핵심 숫자, 큰 시각, 화면 제목, 경고 문장, 버튼 라벨.
/// 본문·보조·라벨은 기본 굵기로 두어야 굵은 글자가 실제로 눈에 띈다.
/// 전부 굵으면 위계가 사라지고 화면이 답답해진다.
abstract final class AppText {
  /// 번들한 Noto Sans KR. 400/500/700/900 네 굵기를 함께 싣는다.
  /// 시스템 폰트에 기대면 기기마다 900이 없어 제목의 위계가 무너진다.
  static const String fontFamily = 'Noto Sans KR';

  /// 혹시 폰트를 싣지 못한 빌드를 위한 대비책.
  static const List<String> fontFallback = <String>[
    'Noto Sans KR',
    'NotoSansKR',
    // 안드로이드에 실제로 깔려 있는 이름들.
    'Noto Sans CJK KR',
    'NotoSansCJKkr',
    // iOS / 윈도우.
    'Apple SD Gothic Neo',
    'Malgun Gothic',
    'Roboto',
    'sans-serif',
  ];

  static const FontWeight _black = FontWeight.w900;
  static const FontWeight _bold = FontWeight.w700;
  static const FontWeight _medium = FontWeight.w500;
  static const FontWeight _regular = FontWeight.w400;

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    required double height,
    required Color color,
    double letterSpacingEm = 0,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
      letterSpacing: size * letterSpacingEm,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
    );
  }

  /// 핵심 숫자 (심박, 비율). 68–76px / 900.
  static TextStyle hero({
    double size = 68,
    Color color = AppColors.textPrimary,
  }) => _base(
    size: size,
    weight: _black,
    height: 1,
    color: color,
    letterSpacingEm: -0.03,
  );

  /// 큰 시각 ("저녁 6시"). 36–38px / 900.
  static TextStyle bigTime({
    double size = 36,
    Color color = AppColors.textPrimary,
  }) => _base(
    size: size,
    weight: _black,
    height: 1,
    color: color,
    letterSpacingEm: -0.02,
  );

  /// 화면 제목. 24–28px / 900.
  static TextStyle screenTitle({
    double size = 28,
    Color color = AppColors.textPrimary,
  }) => _base(
    size: size,
    weight: _black,
    height: 1.35,
    color: color,
    letterSpacingEm: -0.01,
  );

  /// 강조 문장 (경고, 안내). 25–27px / 900.
  static TextStyle emphasis({
    double size = 25,
    Color color = AppColors.textPrimary,
  }) => _base(
    size: size,
    weight: _black,
    height: 1.4,
    color: color,
    letterSpacingEm: -0.01,
  );

  /// 카드 제목 / 리스트 항목. 20–21px / 700.
  /// 화면에서 가장 강해야 하는 제목은 [screenTitle]이나 [emphasis]를 쓴다.
  static TextStyle cardTitle({
    double size = 20,
    Color color = AppColors.textPrimary,
    FontWeight? weight,
  }) => _base(
    size: size,
    weight: weight ?? _bold,
    height: 1.4,
    color: color,
  );

  /// 버튼 라벨. 22–25px / 900.
  static TextStyle button({double size = 24, Color color = Colors.white}) =>
      _base(size: size, weight: _black, height: 1, color: color);

  /// 본문. 19px / 400. 강조가 필요하면 [weight]로만 올린다.
  static TextStyle body({
    double size = 19,
    Color color = AppColors.textBody,
    FontWeight? weight,
  }) => _base(
    size: size,
    weight: weight ?? _regular,
    height: 1.6,
    color: color,
  );

  /// 라벨. 18px / 500. 눌러야 하는 행의 제목만 [weight]로 700을 준다.
  static TextStyle label({
    double size = 18,
    Color color = AppColors.textSecondary,
    FontWeight? weight,
  }) => _base(
    size: size,
    weight: weight ?? _medium,
    height: 1.5,
    color: color,
  );

  /// 보조. 17–17.5px / 500. **이 아래로 내려가지 않는다.**
  static TextStyle caption({
    double size = 17.5,
    Color color = AppColors.textTertiary,
    FontWeight? weight,
  }) => _base(
    size: size,
    weight: weight ?? _regular,
    height: 1.6,
    color: color,
  );

  /// 탭 라벨. 16px, 활성 700 / 비활성 500.
  static TextStyle tab({required bool active}) => _base(
    size: 16,
    weight: active ? _bold : _medium,
    height: 1,
    color: active ? AppColors.point : AppColors.inactiveLabel,
  );
}
