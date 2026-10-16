import 'package:flutter/material.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../profile/presentation/screens/account_screen.dart';
import '../../../profile/presentation/screens/help_screen.dart';
import '../../../profile/presentation/screens/policy_screen.dart';

class GuardianSettingsScreen extends StatelessWidget {
  const GuardianSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final items = <(String, WidgetBuilder)>[
      ('계정 관리', (_) => const AccountScreen(isGuardian: true)),
      ('도움말', (_) => const HelpScreen()),
      ('이용약관', (_) => const PolicyScreen.terms()),
      ('개인정보처리방침', (_) => const PolicyScreen.privacy()),
    ];
    return Scaffold(
      body: Column(
        children: [
          const SeniorBackHeader(title: '설정', alignStart: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SeniorCard(
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SeniorDivider(),
                      SeniorListRow(
                        label: items[i].$1,
                        trailing: const SeniorChevron(),
                        onTap: () => Navigator.of(
                          context,
                        ).push(MaterialPageRoute<void>(builder: items[i].$2)),
                      ),
                    ],
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
