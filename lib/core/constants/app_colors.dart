import 'package:flutter/material.dart';

/// 알콩약콩 시니어 리디자인 색 토큰.
///
/// 원칙: 화면의 90%는 무채색이고, 포인트 파랑([point])은
/// ① 오늘 날짜 ② 활성 탭 ③ 핵심 버튼 ④ 완료 체크에만 쓴다.
/// 위험 경고만 [danger]. 그 외 어떤 색도 추가하지 않는다.
///
/// 보호자 모드 전용 색은 폐기했다. 역할 구분은 색이 아니라
/// 탭 라벨(환자: 오늘·기록·내 정보 / 보호자: 현황·알림·내 정보)과
/// 상단 "보호자 화면" 라벨로 한다.
abstract final class AppColors {
  /// 오늘 날짜, 활성 탭, 핵심 버튼 배경, 완료 체크.
  static const Color point = Color(0xFF1F42E5);

  /// 핵심 버튼 눌림 상태.
  static const Color pointPressed = Color(0xFF1836C4);

  /// 완료 배지 배경, 강조 안내 박스.
  static const Color pointTint = Color(0xFFEDEEFB);

  /// 위험 경고 전용 (약 함께먹기 주의, 미복약 알림).
  static const Color danger = Color(0xFFC0392B);

  /// 위험 버튼 눌림 상태.
  static const Color dangerPressed = Color(0xFFA32E22);

  /// 주의 카드 테두리.
  static const Color dangerBorder = Color(0xFFE8C4BE);

  /// 제목, 핵심 숫자.
  static const Color textPrimary = Color(0xFF111114);

  /// 본문.
  static const Color textBody = Color(0xFF3A3A42);

  /// 라벨.
  static const Color textSecondary = Color(0xFF5C5C66);

  /// 보조 — 흰 배경에서 4.6:1. 이보다 옅은 회색은 쓰지 않는다.
  static const Color textTertiary = Color(0xFF8A8A93);

  /// 화면 배경.
  static const Color bg = Color(0xFFF2F2F6);

  /// 카드.
  static const Color surface = Color(0xFFFFFFFF);

  /// 상단/하단 바.
  static const Color headerBg = Color(0xFFF7F7FA);

  /// 카드 내부 구분선.
  static const Color divider = Color(0xFFEDEDF1);

  /// 바 경계, 비활성 테두리.
  static const Color border = Color(0xFFE4E4EA);

  /// 강조 테두리 (되돌리기·보조 버튼).
  static const Color strongBorder = Color(0xFFD4D4DC);

  /// 비활성 탭 아이콘.
  static const Color inactive = Color(0xFFC6C6CE);

  /// 비활성 탭 라벨.
  static const Color inactiveLabel = Color(0xFF7A7A83);

  /// 비활성 날짜 칩.
  static const Color chipBg = Color(0xFFE8E8EE);

  /// 차트의 지난 막대.
  static const Color chartPast = Color(0xFFDDDDE6);

  /// 잠금화면 배경.
  static const Color lockBg = Color(0xFF1A1B22);

  /// 카메라 뷰파인더 배경.
  static const Color cameraBg = Color(0xFF111114);

  /// 어두운 화면 위의 보조 면.
  static const Color darkSurface = Color(0xFF2A2A31);

  /// 어두운 화면 위의 밝은 글자.
  static const Color onDarkMuted = Color(0xFFC6C6CE);

  /// `›` 셰브런.
  static const Color chevron = Color(0xFFB0B0B8);
}

// ════════════════════════════════════════════════════════════════
//  구버전 상수 별칭
//  아직 리디자인이 닿지 않은 화면이 참조하고 있어 남겨둔다.
//  값은 모두 새 토큰을 가리키므로 그 화면들도 새 팔레트로 보인다.
//  새 코드에서는 [AppColors]를 직접 쓸 것.
// ════════════════════════════════════════════════════════════════
const Color kPrimary = AppColors.point;
const Color kPrimaryLight = AppColors.pointTint;
const Color kPrimaryDark = AppColors.pointPressed;
const Color kBackground = AppColors.bg;
const Color kCard = AppColors.surface;
const Color kText = AppColors.textPrimary;
const Color kTextSub = AppColors.textTertiary;
const Color kGuardian = AppColors.point;
const Color kGuardianLight = AppColors.pointTint;
const Color kBorder = AppColors.border;
const Color kOrange = AppColors.danger;
const Color kOrangeLight = Color(0xFFFAEFED);
const Color kRed = AppColors.danger;
const Color kRedLight = Color(0xFFFAEFED);
const Color kPink = AppColors.danger;
const Color kPinkLight = Color(0xFFFAEFED);
const Color kGreen = AppColors.point;
const Color kGreenLight = AppColors.pointTint;
const Color kBlue = AppColors.point;
const Color kBlueLight = AppColors.pointTint;
