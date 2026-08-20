import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/providers/user_role.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../dashboard/presentation/screens/settings_menu.dart';
import '../../../medication/application/medication_controller.dart';
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
  bool _loudAlarm = true;

  void _todo(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name — 아직 준비 중이에요')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(medicationProvider);
    final age = DateTime.now().year - widget.birthYear;
    final medicineCount = today.doses
        .expand((d) => d.medicines.map((m) => m.ingredient))
        .toSet()
        .length;

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
                        onPressed: () => _todo('내 정보 고치기'),
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
                        value: '$medicineCount가지',
                        trailing: const SeniorChevron(),
                        onTap: () => _todo('내 약 목록'),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '약 먹는 시간',
                        value: '하루 ${today.doses.length}번',
                        trailing: const SeniorChevron(),
                        onTap: () => _todo('약 먹는 시간'),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '가슴에 차는 띠',
                        value: '연결됨',
                        valueColor: AppColors.point,
                        trailing: const SeniorChevron(),
                        onTap: () => context.push('/biosignal'),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '듣고 말하기',
                        value: '켜기',
                        valueColor: AppColors.point,
                        trailing: const SeniorChevron(),
                        onTap: () => context.push('/voice'),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '알림 소리 · 크게',
                        trailing: SeniorToggle(
                          value: _loudAlarm,
                          semanticLabel: '알림 소리를 크게',
                          onChanged: (v) => setState(() => _loudAlarm = v),
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
                      Text('함께 보는 가족', style: AppText.cardTitle(size: 19)),
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
                      SeniorButton(
                        label: '가족 더 초대하기',
                        kind: SeniorButtonKind.secondary,
                        minHeight: 58,
                        fontSize: 20,
                        onPressed: () => _todo('가족 초대'),
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
                    trailing: const SeniorChevron(),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountScreen(),
                      ),
                    ),
                  ),
                ),

                if (widget.isGuardian) ...[
                  const SizedBox(height: 12),
                  SeniorButton(
                    label: '어르신 화면으로 바꾸기',
                    kind: SeniorButtonKind.outline,
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
                    kind: SeniorButtonKind.outline,
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
