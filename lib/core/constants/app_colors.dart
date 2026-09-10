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

  /// 하단 탭바. 상단 헤더는 흰색([surface])이다.
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

  /// `›` 셰브런, 입력 플레이스홀더.
  static const Color chevron = Color(0xFFB0B0B8);

  // ── 파랑 계열 ──────────────────────────────────────────
  /// 쉬운 모드 배지·선택 칩의 테두리.
  static const Color pointBorder = Color(0xFF1730A8);

  /// [pointTint] 카드 위 본문. 연한 파랑 위에서 대비를 확보한다.
  static const Color pointInk = Color(0xFF3A4590);

  /// 파랑 채움 위의 보조 설명 텍스트.
  static const Color onPointMuted = Color(0xFFC9D3FF);

  // ── 위험 계열 ──────────────────────────────────────────
  /// 오류 메시지 배경, 달력의 빠뜨린 날.
  static const Color dangerBg = Color(0xFFFBEAE7);

  /// 경고 톤 카드 배경(약함), 상담 면책 문구 배경.
  static const Color dangerBgSoft = Color(0xFFFDF3F1);

  /// 심박수 이상 화면 헤더 배경과 그 아래 1px 선.
  static const Color dangerHeaderBg = Color(0xFFFBF2F1);
  static const Color dangerHeaderBorder = Color(0xFFEDD9D6);

  /// 붉은 큰 수치 옆 단위 텍스트.
  static const Color dangerMuted = Color(0xFFA8746E);

  // ── 면과 선 ────────────────────────────────────────────
  /// 보조 버튼 채움과 눌림.
  static const Color secondaryFill = Color(0xFFE7E8F0);
  static const Color secondaryPressed = Color(0xFFDCDDE8);

  /// 보조 버튼 2px 테두리. 테두리 없는 연회색 버튼은 만들지 않는다.
  static const Color strongLine = Color(0xFFC6C9DA);

  /// 카드 안 한 단계 더 들어간 블록. 탭바 배경이기도 하다.
  static const Color sunken = Color(0xFFF7F7FA);

  /// 중립 버튼 눌림.
  static const Color neutralPressed = Color(0xFFE8E8EE);

  // ── 어두운 면 ──────────────────────────────────────────
  /// 바텀시트 뒤 배경.
  static const Color scrim = Color(0x73111114);

  /// 잠금화면 배경.
  static const Color lockBg = Color(0xFF1A1B22);

  /// 카메라 화면의 어두운 칩·버튼.
  static const Color camChip = Color(0xFF2A2A31);

  /// 스낵바 배경과 그 안의 체크 아이콘.
  static const Color snackbarBg = Color(0xFF221F1B);
  static const Color snackbarCheck = Color(0xFF8FE3B0);
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
