import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/mode/app_mode.dart';
import '../../../../core/providers/user_role.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../dashboard/presentation/screens/profile_edit_screen.dart';
import '../../../dashboard/presentation/screens/settings_menu.dart';
import '../../../guardian/data/guardian_repository.dart';
import '../../../guardian/presentation/widgets/add_care_sheet.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../reminder/presentation/screens/alarm_settings_screen.dart';
import '../../../../core/session/auth_session.dart';
import '../../../biosignal/domain/heart_data.dart';
import '../../../biosignal/presentation/screens/polar_screen.dart';
import '../../../dur_analysis/presentation/screens/dur_analysis_screen.dart';
import '../../../medicines/application/user_medicines_controller.dart';
import '../widgets/logout_sheet.dart';
import 'account_screen.dart';

/// 4h — 내 정보 · 설정.
///
/// 로그아웃·탈퇴 같은 위험 동작은 이 화면에 두지 않는다.
/// [AccountScreen]으로 분리하고, 안전한 버튼과 물리적으로 떨어뜨렸다.
class MyPageScreen extends ConsumerStatefulWidget {
  /// 보호자 화면에서 열렸는지. 문구만 달라지고 색은 같다.
  final bool isGuardian;

  final String userName;
  final int birthYear;

  const MyPageScreen({
    super.key,
    this.isGuardian = false,
    this.userName = '김복자',
    this.birthYear = 1958,
  });

  @override
  ConsumerState<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends ConsumerState<MyPageScreen> {
  /// 로그아웃하면 일반 모드로 되돌린다.
  /// 다음 사람이 쉬운 모드에 갇힌 채로 로그인 화면을 만나지 않도록.
  Future<void> _logout() async {
    final confirmed = await showLogoutSheet(context);
    if (!confirmed || !mounted) return;
    await ref.read(appModeProvider.notifier).set(AppMode.normal);
    await AuthSession.logout();
    if (mounted) context.go('/login');
  }

  /// 39 시트를 그대로 쓴다. 보호자 화면에 있는 것과 같은 길이다.
  Future<void> _inviteFamily() async {
    final draft = await showAddCareSheet(context);
    if (draft == null || !mounted) return;
    final result = await GuardianRepository().invite(
      name: draft.name,
      relation: draft.relation,
      phone: draft.phone,
    );
    if (!mounted) return;
    // 서버가 받아 준 뒤에만 보냈다고 말한다.
    showSeniorSnackbar(
      context,
      result.isSent
          ? '${draft.name} 님에게 초대를 보냈어요'
          : result.error ?? '초대를 보내지 못했어요',
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(medicationProvider);
    final mode = ref.watch(appModeProvider);
    final medicines = ref.watch(userMedicinesProvider);
    final age = DateTime.now().year - widget.birthYear;
    final medicineCount = medicines.maybeWhen(
      data: (items) => items.length,
      orElse: () => today.doses
          .expand((d) => d.medicines.map((m) => m.medicineCode ?? m.ingredient))
          .toSet()
          .length,
    );

    return Column(
      children: [
        const SeniorTitleHeader(title: '내 정보'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 프로필 ──
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  child: Row(
                    children: [
                      InitialAvatar(
                        name: widget.userName,
                        size: 64,
                        background: AppColors.pointTint,
                        foreground: AppColors.point,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.userName,
                              style: AppText.cardTitle(size: 23),
                            ),
                            Text(
                              '${widget.birthYear}년생 · $age세',
                              style: AppText.body(
                                size: 18,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SeniorTextButton(
                        label: '고치기',
                        expand: false,
                        color: AppColors.point,
                        fontSize: 18,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ProfileEditScreen(
                              isGuardian: widget.isGuardian,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── 화면 모드 ──
                // 토글이 아니라 세그먼트다. 지금 어느 쪽인지가 늘 보인다.
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('화면 모드', style: AppText.cardTitle(size: 20)),
                      const SizedBox(height: 6),
                      Text(
                        mode.isEasy
                            ? '다음 할 일 버튼 하나만 따라가면 됩니다'
                            : '버튼 하나만 따라가는 쉬운 화면으로 바꿀 수 있어요',
                        style: AppText.caption(size: 17.5),
                      ),
                      const SizedBox(height: 14),
                      SeniorSegmented(
                        labels: const ['일반', '쉬운 화면'],
                        index: mode.isEasy ? 1 : 0,
                        onChanged: (i) => ref
                            .read(appModeProvider.notifier)
                            .set(i == 1 ? AppMode.easy : AppMode.normal),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── 설정 목록 ──
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      SeniorListRow(
                        label: '내 약 목록',
                        icon: TablerIcons.pill,
                        value: '$medicineCount가지',
                        trailing: const SeniorChevron(),
                        onTap: () => context.push('/my-medicines'),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '약 함께먹기 주의',
                        icon: TablerIcons.alert_triangle,
                        iconColor: AppColors.danger,
                        value: '1건',
                        valueColor: AppColors.danger,
                        trailing: const SeniorChevron(),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DurAnalysisScreen(),
                          ),
                        ),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '복약 알림',
                        icon: TablerIcons.bell,
                        // 소리로 알려주기만 한다. 말로 기록하는 기능은 없다.
                        subtitle: '아침 8시 · 저녁 6시 · 소리로 알려드려요',
                        trailing: const SeniorChevron(),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AlarmSettingsScreen(
                              userName: widget.userName,
                              guardianTitle:
                                  '${today.guardianRelation} '
                                  '${today.guardianName} 님',
                            ),
                          ),
                        ),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '폴라 베리티 센스',
                        icon: TablerIcons.heart,
                        // 제품명이 길어 값을 옆에 붙이면 이름이 잘린다.
                        subtitle: '연결됨 · 심박 센서',
                        subtitleColor: AppColors.point,
                        trailing: const SeniorChevron(),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PolarScreen(data: HeartData.demo),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── 함께 보는 가족 ──
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IconTitle(
                        icon: TablerIcons.users,
                        text: '함께 보는 가족',
                        style: AppText.cardTitle(size: 19),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          InitialAvatar(
                            name: today.guardianName,
                            size: 48,
                            background: AppColors.bg,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${today.guardianRelation} '
                                  '${today.guardianName}',
                                  style: AppText.cardTitle(),
                                ),
                                Text(
                                  '약 드신 것과 심장 박동을 볼 수 있어요',
                                  style: AppText.caption(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // 보호자 계정은 따로 있다. 여기서 열리지 않는다는 사실을
                      // 미리 적어 두지 않으면 "안 열린다"는 문의가 된다.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.sunken,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${today.guardianName} 님은 따로 가입한 보호자 계정으로 봅니다. '
                          '어르신 화면에서는 보호자 화면이 열리지 않아요.',
                          style: AppText.body(size: 17.5),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SeniorButton(
                        label: '가족 더 초대하기',
                        kind: SeniorButtonKind.secondary,
                        minHeight: 58,
                        fontSize: 20,
                        onPressed: _inviteFamily,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── 도움말 ──
                const SettingsMenu(),
                const SizedBox(height: 12),

                // ── 계정 (위험 동작은 하위 화면으로 분리) ──
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 4,
                  ),
                  child: SeniorListRow(
                    label: '계정 관리',
                    icon: TablerIcons.user,
                    trailing: const SeniorChevron(),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // 눈에 띄지 않게, 그러나 찾을 수 있게. 회색 글씨 한 줄.
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 4,
                  ),
                  child: SeniorListRow(
                    label: '로그아웃',
                    labelColor: AppColors.textTertiary,
                    trailing: const SeniorChevron(),
                    onTap: _logout,
                  ),
                ),

                if (widget.isGuardian) ...[
                  const SizedBox(height: 12),
                  SeniorButton(
                    label: '어르신 화면으로 바꾸기',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 58,
                    fontSize: 20,
                    onPressed: () => ref
                        .read(userRoleProvider.notifier)
                        .state = UserRole.patient,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  SeniorButton(
                    label: '보호자 화면으로 바꾸기',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 58,
                    fontSize: 20,
                    onPressed: () => ref
                        .read(userRoleProvider.notifier)
                        .state = UserRole.guardian,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
