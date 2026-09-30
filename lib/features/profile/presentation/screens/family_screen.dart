import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../guardian/application/guardians_provider.dart';
import '../../../guardian/data/guardian_repository.dart';
import '../../../medication/application/medication_controller.dart';

/// 함께 보는 가족 — 시안 60.
///
/// 내 정보 안에 카드로 접혀 있던 것을 한 화면으로 냈다. 가족을 더하고
/// 빼는 일은 자주 하지 않지만, 할 때는 이 한 장만 보면 되게 둔다.
class FamilyScreen extends ConsumerWidget {
  /// 가족을 초대하는 시트를 여는 길. 내 정보가 이미 갖고 있어 넘겨받는다.
  final Future<void> Function() onInvite;

  const FamilyScreen({super.key, required this.onInvite});

  /// 보호자가 먼저 청한 연결에 대답한다. 거절은 요청을 지운다.
  Future<void> _answer(
    BuildContext context,
    WidgetRef ref,
    GuardianContact guardian,
    bool accept,
  ) async {
    final repository = GuardianRepository();
    try {
      if (accept) {
        await repository.accept(guardian.id);
      } else {
        await repository.remove(guardian.id);
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        showSeniorSnackbar(context, error.message, error: true);
      }
      return;
    }
    if (!context.mounted) return;
    ref.invalidate(guardiansProvider);
    ref.read(medicationProvider.notifier).refreshFromServer();
    showSeniorSnackbar(
      context,
      accept
          ? '${guardian.name} 님이 이제 함께 볼 수 있어요'
          : '${guardian.name} 님의 요청을 거절했어요',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardians = ref.watch(guardiansProvider);
    final list = guardians.valueOrNull ?? const <GuardianContact>[];

    return Scaffold(
      body: Column(
        children: [
          const SeniorBackHeader(title: '함께 보는 가족'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (guardians.isLoading && list.isEmpty)
                    Text('불러오는 중이에요', style: AppText.caption(size: 18))
                  else if (guardians.hasError && list.isEmpty)
                    Text(
                      '가족 목록을 불러오지 못했어요',
                      style: AppText.caption(size: 18, color: AppColors.danger),
                    )
                  else if (list.isEmpty)
                    SeniorCard(
                      radius: 26,
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        '아직 함께 보는 가족이 없어요.\n'
                        '초대하면 약을 놓쳤을 때 알려드려요.',
                        style: AppText.body(size: 19),
                      ),
                    )
                  else
                    for (int i = 0; i < list.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _FamilyRow(
                        guardian: list[i],
                        onAnswer: (accept) =>
                            _answer(context, ref, list[i], accept),
                      ),
                    ],
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      list.isEmpty
                          ? '가족을 더하시면 약을 안 드시거나 심박수가 빠를 때 '
                                '그분께 자동으로 알려드려요.'
                          : '약을 안 드시거나 심박수가 빠르면 '
                                '이분들께 자동으로 알려드려요.',
                      style: AppText.body(
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SeniorButton(
                    label: list.isEmpty ? '가족 추가하기' : '가족 더 추가하기',
                    icon: TablerIcons.user_plus,
                    minHeight: 70,
                    fontSize: 22,
                    elevated: true,
                    onPressed: onInvite,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 가족 한 줄. 보호자가 먼저 청한 연결이면 수락·거절을 아래에 붙인다.
class _FamilyRow extends StatelessWidget {
  final GuardianContact guardian;
  final ValueChanged<bool> onAnswer;

  const _FamilyRow({required this.guardian, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final waiting = guardian.awaitsMyAnswer;
    return SeniorCard(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.pointTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  TablerIcons.users,
                  size: 28,
                  color: AppColors.point,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(guardian.label, style: AppText.cardTitle(size: 21)),
                    const SizedBox(height: 2),
                    Text(
                      waiting ? '함께 보기를 요청했어요' : '약 드신 것과 심박수를 함께 봐요',
                      style: AppText.body(size: 17, color: AppColors.point),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (waiting) ...[
            const SizedBox(height: 12),
            // 수락하면 이 분이 복약·심장 박동을 보게 된다. 거절이 옆에 같이 있다.
            Row(
              children: [
                Expanded(
                  child: SeniorButton(
                    label: '수락',
                    minHeight: 56,
                    fontSize: 20,
                    onPressed: () => onAnswer(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SeniorButton(
                    label: '거절',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 56,
                    fontSize: 20,
                    onPressed: () => onAnswer(false),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
