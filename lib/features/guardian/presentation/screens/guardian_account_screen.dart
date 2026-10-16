import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../dashboard/presentation/screens/profile_edit_screen.dart';
import '../../../profile/application/current_user_controller.dart';

/// Profile editing only. Account actions belong in Settings.
class GuardianAccountScreen extends ConsumerWidget {
  const GuardianAccountScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider).valueOrNull;
    void edit() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ProfileEditScreen(isGuardian: true),
      ),
    );
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '내 계정', alignStart: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SeniorCard(
                child: Column(
                  children: [
                    SeniorListRow(
                      label: '이름',
                      value: profile?.name ?? '',
                      trailing: const SeniorChevron(),
                      onTap: edit,
                    ),
                    const SeniorDivider(),
                    SeniorListRow(
                      label: '휴대폰',
                      value: profile?.phone ?? '',
                      trailing: const SeniorChevron(),
                      onTap: edit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
