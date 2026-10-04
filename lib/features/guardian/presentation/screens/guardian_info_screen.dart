import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/coach_marks.dart';
import '../../../../core/widgets/help_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../profile/application/current_user_controller.dart';
import '../../../profile/presentation/screens/help_screen.dart';
import '../../../profile/presentation/screens/policy_screen.dart';
import '../../application/guardians_provider.dart';
import 'guardian_account_screen.dart';
import 'guardian_alert_prefs_screen.dart';
import 'care_manage_screen.dart';

/// 보호자 · 정보 탭 (프로토타입 93).
///
/// 어르신 화면의 "내 정보"와 다르다. 보호자는 약을 먹지 않으니
/// 내 약 목록·복약 알림·폴라 센서가 없다.
class GuardianInfoScreen extends ConsumerStatefulWidget {
  const GuardianInfoScreen({super.key});

  @override
  ConsumerState<GuardianInfoScreen> createState() => _GuardianInfoScreenState();
}

class _GuardianInfoScreenState extends ConsumerState<GuardianInfoScreen> {
  // 도움말이 동그라미를 칠 자리들.
  final _accountKey = GlobalKey();
  final _menuKey = GlobalKey();

  /// 이 화면을 짚어 가며 설명한다.
  void _showHelp() {
    CoachMarks.show(context, [
      CoachMark(
        target: _accountKey,
        title: '내 계정',
        body: '누르면 이름과 전화번호를 고치고, 로그아웃하거나 탈퇴할 수 있어요.',
        boxed: true,
      ),
      CoachMark(
        target: _menuKey,
        title: '돌보는 분과 알림',
        body:
            '"돌보는 분 관리"에서 어르신을 더하거나 뺍니다. '
            '"알림 받는 방법"에서 어떤 일에 알림을 받을지 고릅니다.',
        boxed: true,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final profile = user.valueOrNull;
    final patients =
        ref.watch(careOverviewProvider).valueOrNull?.patients ?? const [];

    return Column(
      children: [
        SeniorTitleHeader(
          title: '정보',
          trailing: HelpButton(onTap: _showHelp, size: 52),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SeniorCard(
                  key: _accountKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const GuardianAccountScreen(),
                    ),
                  ),
                  child: Row(
                    children: [
                      InitialAvatar(
                        name: profile?.name ?? '',
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
                              profile?.name ?? '불러오는 중이에요',
                              style: AppText.cardTitle(size: 23),
                            ),
                            if ((profile?.phone ?? '').isNotEmpty)
                              Text(
                                profile!.phone!,
                                style: AppText.body(
                                  size: 18,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const SeniorChevron(),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SeniorCard(
                  key: _menuKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      SeniorListRow(
                        label: '돌보는 분 관리',
                        icon: TablerIcons.users,
                        value: patients.isEmpty ? null : '${patients.length}명',
                        trailing: const SeniorChevron(),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CareManageScreen(),
                          ),
                        ),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '알림 받는 방법',
                        icon: TablerIcons.bell,
                        trailing: const SeniorChevron(),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const GuardianAlertPrefsScreen(),
                          ),
                        ),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '도움말',
                        icon: TablerIcons.help_circle,
                        trailing: const SeniorChevron(),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const HelpScreen(),
                          ),
                        ),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '약관 · 개인정보',
                        icon: TablerIcons.file_text,
                        trailing: const SeniorChevron(),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PolicyScreen.terms(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
