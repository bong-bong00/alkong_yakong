import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../dashboard/presentation/screens/profile_edit_screen.dart';
import '../../application/current_user_controller.dart';
import '../../application/session_actions.dart';

/// 내 계정 — 내 정보 한눈에 보기와 로그아웃·탈퇴.
///
/// 위험 동작을 "내 정보"에서 떼어내 여기로 옮겼다.
/// 안전한 버튼(가족 초대, 약 목록)과 물리적으로 떨어져 있어야
/// 잘못 누르는 일이 줄어든다. 여기서도 둘은 "계정 정리"로 따로 묶고,
/// 누르면 무엇이 일어나는지 한 번 더 묻는다.
class AccountScreen extends ConsumerWidget {
  /// 보호자 화면에서 열렸는지. 고치기 화면의 묻는 말이 달라진다.
  final bool isGuardian;

  const AccountScreen({super.key, this.isGuardian = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider).valueOrNull;

    void edit() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileEditScreen(isGuardian: isGuardian),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '내 계정'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text('내 정보', style: AppText.label(size: 18)),
                  ),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        SeniorListRow(
                          label: '이름',
                          // 아직 못 읽었으면 값을 비워 둔다. 모르는 것을
                          // "-"로 적으면 지워진 것처럼 읽힌다.
                          value: profile?.name,
                          trailing: const SeniorChevron(),
                          onTap: edit,
                        ),
                        const SeniorDivider(),
                        SeniorListRow(
                          label: '휴대폰',
                          value: profile?.phone,
                          trailing: const SeniorChevron(),
                          onTap: edit,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text('계정 정리', style: AppText.label(size: 18)),
                  ),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        SeniorListRow(
                          label: '이 전화기에서 로그아웃',
                          trailing: const SeniorChevron(),
                          onTap: () => _confirmLogout(context, ref),
                        ),
                        const SeniorDivider(),
                        SeniorListRow(
                          label: '탈퇴하기',
                          labelColor: AppColors.danger,
                          trailing: const SeniorChevron(),
                          onTap: () => _confirmWithdraw(context, ref),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '로그아웃해도 기록은 그대로 남아요.\n'
                    '탈퇴하면 복약 기록과 등록한 약이 모두 지워집니다.',
                    textAlign: TextAlign.center,
                    style: AppText.caption(size: 17),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final stay = await showSeniorYesNoDialog(
      context: context,
      title: '이 전화기에서 로그아웃할까요?',
      message: '다시 들어오시려면 휴대폰 번호와 비밀번호가 필요해요. 기록은 그대로 남아 있어요.',
      yesLabel: '아니요, 그냥 둘게요',
      noLabel: '네, 로그아웃할게요',
    );
    if (stay || !context.mounted) return;
    await endSession(ref);
    if (context.mounted) context.go('/login');
  }

  Future<void> _confirmWithdraw(BuildContext context, WidgetRef ref) async {
    final go = await showSeniorYesNoDialog(
      context: context,
      title: '정말 탈퇴하시겠어요?',
      message: '지금까지의 복약 기록이 모두 지워져요. 한 번 지우면 되돌릴 수 없어요.',
      yesLabel: '아니요, 그냥 둘게요',
      noLabel: '네, 탈퇴할게요',
    );
    // 위쪽(주 버튼)이 "그냥 둘게요"다. 위험한 쪽을 크게 두지 않는다.
    if (go || !context.mounted) return;
    await _withdraw(context, ref);
  }

  /// 서버에서 지워진 뒤에만 나간다. 못 지웠는데 나가면
  /// 그만둔 줄 알았던 계정이 그대로 남는다.
  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final userId =
        ref.read(currentUserProvider).valueOrNull?.id ??
        MvpSession.userId.trim();
    try {
      await ref.read(userRepositoryProvider).delete(userId);
    } on ApiException catch (error) {
      if (context.mounted) {
        showSeniorSnackbar(context, error.message, error: true);
      }
      return;
    }
    await endSession(ref);
    if (context.mounted) context.go('/login');
  }
}
