import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/session/auth_session.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';

/// 계정 관리 — 로그아웃·탈퇴 전용 하위 화면.
///
/// 위험 동작을 "내 정보"에서 떼어내 여기로 옮겼다.
/// 안전한 버튼(가족 초대, 약 목록)과 물리적으로 떨어져 있어야
/// 잘못 누르는 일이 줄어든다.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '계정 관리'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('이 전화기에서 나가기', style: AppText.cardTitle()),
                        const SizedBox(height: 6),
                        Text(
                          '다시 들어오시려면 휴대폰 번호와 비밀번호가 필요해요. '
                          '기록은 그대로 남아 있어요.',
                          style: AppText.body(),
                        ),
                        const SizedBox(height: 16),
                        SeniorButton(
                          label: '나가기',
                          kind: SeniorButtonKind.outline,
                          minHeight: 62,
                          fontSize: 21,
                          onPressed: () async {
                            await AuthSession.logout();
                            if (context.mounted) context.go('/login');
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 20,
                    ),
                    borderColor: AppColors.dangerBorder,
                    borderWidth: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '아주 그만두기',
                          style: AppText.cardTitle(color: AppColors.danger),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '그만두시면 복약 기록과 등록한 약이 모두 지워지고 '
                          '되돌릴 수 없어요. 가족에게도 더 이상 알림이 가지 않아요.',
                          style: AppText.body(),
                        ),
                        const SizedBox(height: 16),
                        SeniorButton(
                          label: '그만두기',
                          kind: SeniorButtonKind.danger,
                          minHeight: 62,
                          fontSize: 21,
                          onPressed: () => _confirmWithdraw(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmWithdraw(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('정말 그만두시겠어요?', style: AppText.emphasis(size: 25)),
              const SizedBox(height: 10),
              Text(
                '지금까지의 복약 기록이 모두 지워져요. '
                '한 번 지우면 되돌릴 수 없어요.',
                style: AppText.body(),
              ),
              const SizedBox(height: 20),
              SeniorButton(
                label: '아니요, 그냥 둘게요',
                minHeight: 62,
                fontSize: 21,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              const SizedBox(height: 10),
              SeniorButton(
                label: '네, 그만둘게요',
                kind: SeniorButtonKind.secondary,
                minHeight: 58,
                fontSize: 20,
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  // TODO: 백엔드 회원 탈퇴 API 연동.
                  await AuthSession.logout();
                  if (context.mounted) context.go('/login');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
