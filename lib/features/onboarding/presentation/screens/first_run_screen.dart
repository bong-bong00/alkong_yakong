import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';

/// 5g — 첫 사용 · 가족이 대신 설정.
///
/// 처방전 촬영은 어르신이 혼자 성공하기 가장 어려운 관문이다.
/// 가족 대행을 부가 기능이 아니라 **1급 경로**로 올린다.
class FirstRunScreen extends StatelessWidget {
  const FirstRunScreen({super.key});

  void _askFamily(BuildContext context) {
    // TODO: 가족에게 SMS/카카오톡 초대 링크 발송 → 가족이 자기 기기에서
    //       촬영·확인 → 어르신 앱에 "약이 등록됐어요" 알림.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('가족에게 보낼 초대 문자를 준비하고 있어요')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '약 등록만 하면\n준비가 끝나요',
                style: AppText.screenTitle(size: 32),
              ),
              const SizedBox(height: 10),
              Text(
                '약을 한 번만 넣어두면, 그다음부터는 시간에 맞춰 '
                '저희가 알려드려요.',
                style: AppText.body(
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // ── 선택지 1 (권장) ──
              SeniorCard(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                radius: 24,
                borderColor: AppColors.point,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: SeniorBadge(
                        label: '가장 쉬운 방법',
                        radius: 10,
                        fontSize: 16,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('가족이 대신 넣어드리기', style: AppText.screenTitle(size: 24)),
                    const SizedBox(height: 6),
                    Text(
                      '자녀분 전화기에서 처방전을 찍으면, '
                      '어르신 전화기에는 알림만 옵니다.',
                      style: AppText.body(size: 18.5),
                    ),
                    const SizedBox(height: 14),
                    SeniorButton(
                      label: '가족에게 부탁하기',
                      minHeight: 70,
                      fontSize: 23,
                      onPressed: () => _askFamily(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── 선택지 2 ──
              SeniorCard(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                radius: 24,
                borderColor: AppColors.border,
                borderWidth: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('제가 직접 찍을게요', style: AppText.screenTitle(size: 24)),
                    const SizedBox(height: 6),
                    Text(
                      '처방전 종이를 전화기로 찍으면 약 이름을 읽어드려요. '
                      '흐리게 찍히면 다시 찍어드릴게요.',
                      style: AppText.body(size: 18.5),
                    ),
                    const SizedBox(height: 14),
                    SeniorButton(
                      label: '처방전 찍기',
                      kind: SeniorButtonKind.secondary,
                      minHeight: 66,
                      fontSize: 22,
                      onPressed: () => context.push('/prescription'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              SeniorTextButton(
                label: '약 이름을 손으로 적을게요',
                color: AppColors.point,
                fontSize: 19,
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('손으로 적기 — 아직 준비 중이에요')),
                ),
              ),
              Text(
                '나중에 바꿀 수 있어요',
                textAlign: TextAlign.center,
                style: AppText.caption(size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
