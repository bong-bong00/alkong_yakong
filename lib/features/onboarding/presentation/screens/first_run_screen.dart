import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../prescription/presentation/widgets/family_request_sheet.dart';

/// 5g — 첫 사용 · 가족이 대신 설정.
///
/// 처방전 촬영은 어르신이 혼자 성공하기 가장 어려운 관문이다.
/// 가족 대행을 부가 기능이 아니라 **1급 경로**로 올린다.
class FirstRunScreen extends StatelessWidget {
  const FirstRunScreen({super.key});

  /// 부탁을 마친 상태로 약 넣기 화면에 들어간다.
  /// 거기서 "딸 지안 님에게 부탁했어요" 확인 카드가 그 자리에 뜬다.
  // TODO: 가족에게 SMS/카카오톡 초대 링크 발송 → 가족이 자기 기기에서
  //       촬영·확인 → 어르신 앱에 "약이 등록됐어요" 알림.
  void _askFamily(BuildContext context) {
    // 어르신 전화기에서 할 일은 없다. 자녀분이 보호자 앱에서 넣어 준다.
    unawaited(
      showFamilyRequestSheet(
        context,
        guardianTitle: resolveGuardianTitle(context, ''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('약 등록만 하면\n준비가 끝나요', style: AppText.screenTitle(size: 32)),
              const SizedBox(height: 10),
              Text(
                '처방전을 찍으면 약과 시간이 자동으로 들어갑니다. '
                '어렵다면 가족이 대신 해드릴 수 있어요.',
                style: AppText.body(size: 20, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),

              // ── 선택지 1 (권장) ──
              SeniorCard(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                radius: 24,
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
                    Text('가족이 대신 등록하기', style: AppText.screenTitle(size: 24)),
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
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                radius: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('처방전 촬영하기', style: AppText.screenTitle(size: 24)),
                    const SizedBox(height: 6),
                    Text(
                      '처방전 종이를 전화기로 찍으면 약 이름을 읽어드려요. '
                      '흐리게 찍히면 다시 찍어드릴게요.',
                      style: AppText.body(size: 18.5),
                    ),
                    const SizedBox(height: 14),
                    SeniorButton(
                      label: '처방전 촬영',
                      kind: SeniorButtonKind.secondary,
                      minHeight: 66,
                      fontSize: 22,
                      // 길은 이 칸에서 이미 골랐다. 들어가서 또 고르게
                      // 하지 않는다.
                      onPressed: () =>
                          context.push('/prescription?start=camera'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── 선택지 3 ──
              // 작은 글자 단추로 두었더니 손으로 적는 길이 없는 줄 알고
              // 그냥 건너뛰셨다. 나머지 둘과 같은 칸으로 세운다.
              SeniorCard(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                radius: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('직접 작성', style: AppText.screenTitle(size: 24)),
                    const SizedBox(height: 6),
                    Text(
                      '처방전이 없어도 괜찮아요. '
                      '약 이름과 복용 시간대만 적으면 됩니다.',
                      style: AppText.body(size: 18.5),
                    ),
                    const SizedBox(height: 14),
                    SeniorButton(
                      label: '약 이름 적기',
                      kind: SeniorButtonKind.secondary,
                      minHeight: 66,
                      fontSize: 22,
                      onPressed: () => context.push('/manual-medicine'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SeniorButton(
                label: '건너뛰기',
                subLabel: '나중에 넣어도 됩니다',
                // 연한 면(#F0F1F5)은 이 화면 바탕과 거의 같은 색이라
                // 단추가 바탕에 묻혔다. 흰 면에 그림자로 띄운다.
                kind: SeniorButtonKind.card,
                minHeight: 66,
                fontSize: 21,
                onPressed: () => context.go('/'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
