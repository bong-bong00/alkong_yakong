import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../dashboard/presentation/screens/profile_edit_screen.dart';
import '../../../dashboard/presentation/screens/settings_menu.dart';
import '../../../guardian/application/guardians_provider.dart';
import '../../../guardian/data/guardian_repository.dart';
import '../../../guardian/presentation/widgets/add_care_sheet.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../reminder/application/alarm_preferences.dart';
import '../../../reminder/presentation/screens/alarm_settings_screen.dart';
import '../../../biosignal/presentation/screens/polar_screen.dart';
import '../../../medicines/application/user_medicines_controller.dart';
import '../../application/current_user_controller.dart';
import 'account_screen.dart';
import 'family_screen.dart';

/// 4h — 내 정보 · 설정.
///
/// 로그아웃·탈퇴 같은 위험 동작은 이 화면에 두지 않는다.
/// [AccountScreen]으로 분리하고, 안전한 버튼과 물리적으로 떨어뜨렸다.
///
/// 이 화면의 글자는 모두 저장된 값에서 온다. 고치고 돌아오면 바로 바뀐다.
class MyPageScreen extends ConsumerStatefulWidget {
  /// 보호자 화면에서 열렸는지. 문구만 달라지고 색은 같다.
  final bool isGuardian;

  const MyPageScreen({super.key, this.isGuardian = false});

  @override
  ConsumerState<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends ConsumerState<MyPageScreen> {
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
    if (result.isSent) {
      ref.invalidate(guardiansProvider);
      ref.read(medicationProvider.notifier).refreshFromServer();
    }
    // 서버가 받아 준 뒤에만 보냈다고 말한다.
    showSeniorSnackbar(
      context,
      result.isSent
          ? '${draft.name} 님에게 초대를 보냈어요'
          : result.error ?? '초대를 보내지 못했어요',
      error: !result.isSent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(medicationProvider);
    final user = ref.watch(currentUserProvider);
    final profile = user.valueOrNull;
    final guardians = ref.watch(guardiansProvider);
    final alarm = ref.watch(alarmPreferencesProvider);
    final medicines = ref.watch(userMedicinesProvider);
    final medicineCount = medicines.maybeWhen(
      data: (items) => items.length,
      orElse: () => today.doses
          .expand((d) => d.medicines.map((m) => m.medicineCode ?? m.ingredient))
          .toSet()
          .length,
    );
    final loadFailed = profile == null && user.hasError;
    final ageLine = profile?.ageLine(DateTime.now()) ?? '';

    return Container(
      color: AppColors.pageBg,
      // 탭으로 열려 머리띠가 없다. 이름이 상태바에 붙지 않게 피한다.
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 이름 ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  profile?.name ??
                                  (loadFailed ? '내 정보' : '불러오는 중이에요'),
                              style: AppText.screenTitle(size: 28),
                            ),
                            if (profile?.name != null)
                              TextSpan(
                                text: ' 님',
                                style: AppText.screenTitle(size: 28).copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── 내 몸 정보 ──
                    _BodyInfoCard(
                      ageLine: ageLine,
                      bloodType: profile?.bloodType,
                      allergies: profile?.allergies ?? const [],
                      diseases: profile?.diseases ?? const [],
                      loadFailed: loadFailed,
                      onRetry: () => ref.invalidate(currentUserProvider),
                      onEdit: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ProfileEditScreen(isGuardian: widget.isGuardian),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 알림 · 센서 · 가족 세 칸 ──
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _SquareTile(
                              icon: TablerIcons.bell,
                              label: '알림',
                              // 소리로 알려주기만 한다. 말로 기록하는 기능은 없다.
                              value: alarm.summary,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const AlarmSettingsScreen(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _SquareTile(
                              icon: TablerIcons.heart,
                              label: '센서',
                              // 연결 여부는 들어가야 안다. 여기서 "연결됨"이라고
                              // 적어 두면 안 차고 계신 분께 거짓말이 된다.
                              value: '차는 방법',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const PolarScreen(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _SquareTile(
                              icon: TablerIcons.users,
                              label: '가족',
                              value: guardians.maybeWhen(
                                data: (list) => '${list.length}명',
                                orElse: () => '보기',
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      FamilyScreen(onInvite: _inviteFamily),
                                ),
                              ),
                            ),
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
                            label: '폴라 센서',
                            icon: TablerIcons.heart,
                            // 여기서는 연결 여부를 모른다. 들어가야 센서를 찾는다.
                            subtitle: '심박 센서 연결 · 차는 방법',
                            trailing: const SeniorChevron(),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PolarScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── 도움말 · 계정, 넓은 두 칸 ──
                    // 위험한 동작(로그아웃·탈퇴)은 계정 화면 안에 둔다.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _WideTile(
                              icon: TablerIcons.help_circle,
                              label: '도움말·약관',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SettingsMenuScreen(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _WideTile(
                              icon: TablerIcons.logout,
                              label: '로그아웃·탈퇴',
                              danger: true,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const AccountScreen(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 어르신·보호자 화면은 가입한 계정의 역할로 정해진다.
                    // 여기서 바꾸는 버튼은 두지 않는다.
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 내 정보 맨 아래 넓은 칸. 아이콘과 이름을 한 줄로 놓는다.
class _WideTile extends StatelessWidget {
  final IconData icon;
  final String label;

  /// 되돌리기 어려운 자리(로그아웃·탈퇴)는 연한 빨강 면으로 둔다.
  /// 누르기 전에 무게가 다르다는 것을 색으로 먼저 알린다.
  final bool danger;
  final VoidCallback onTap;

  const _WideTile({
    required this.icon,
    required this.label,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: danger ? AppColors.dangerBg : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: danger ? null : kCardShadow,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: danger ? AppColors.danger : AppColors.textPrimary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppText.cardTitle(
                      size: 19,
                      color: danger ? AppColors.danger : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 내 정보 가운데 줄의 네모 칸. 아이콘 · 이름 · 지금 값을 쌓는다.
class _SquareTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SquareTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $value',
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 104),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: kCardShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26, color: AppColors.textPrimary),
                const SizedBox(height: 8),
                Text(label, style: AppText.cardTitle(size: 18)),
                const SizedBox(height: 2),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle(size: 16, color: AppColors.point),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 시안 54 — 나이·혈액형·알레르기를 한 줄에 세 칸으로 놓고,
/// 그 아래 앓는 병을 적는다. 고치는 길은 카드 오른쪽 위 하나뿐이다.
class _BodyInfoCard extends StatelessWidget {
  final String ageLine;
  final String? bloodType;
  final List<String> allergies;
  final List<String> diseases;
  final bool loadFailed;
  final VoidCallback onRetry;
  final VoidCallback onEdit;

  const _BodyInfoCard({
    required this.ageLine,
    required this.bloodType,
    required this.allergies,
    required this.diseases,
    required this.loadFailed,
    required this.onRetry,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('내 몸 정보', style: AppText.cardTitle(size: 20)),
              ),
              const SizedBox(width: 10),
              // 알약 모양 단추 하나로 고치는 길을 연다.
              Semantics(
                button: true,
                label: loadFailed ? '다시 불러오기' : '내 정보 고치기',
                child: GestureDetector(
                  onTap: loadFailed ? onRetry : onEdit,
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            loadFailed
                                ? TablerIcons.refresh
                                : TablerIcons.pencil,
                            size: 20,
                            color: AppColors.textPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            loadFailed ? '다시' : '고치기',
                            style: AppText.cardTitle(size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (loadFailed) ...[
            const SizedBox(height: 12),
            Text(
              '내 정보를 불러오지 못했어요',
              style: AppText.body(size: 18, color: AppColors.danger),
            ),
          ] else ...[
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _cell('나이', _age)),
                  Expanded(child: _cell('혈액형', bloodType ?? '모름')),
                  Expanded(child: _cell('알레르기', _first(allergies))),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const SeniorDivider(),
            const SizedBox(height: 12),
            Text(
              '앓는 병 · ${diseases.isEmpty ? '없어요' : diseases.join(', ')}',
              style: AppText.cardTitle(size: 18, color: AppColors.textBody),
            ),
          ],
        ],
      ),
    );
  }

  /// "68세 · 여자"에서 나이만 떼어 쓴다. 칸이 좁아 둘 다 들어가지 않는다.
  String get _age {
    final head = ageLine.split('·').first.trim();
    return head.isEmpty ? '모름' : head;
  }

  /// 여러 개면 첫 것만 적고 나머지는 "외 N"으로 줄인다.
  static String _first(List<String> items) {
    if (items.isEmpty) return '없어요';
    if (items.length == 1) return items.first;
    return '${items.first} 외 ${items.length - 1}';
  }

  Widget _cell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppText.body(size: 17, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(value, style: AppText.cardTitle(size: 20)),
      ],
    );
  }
}
