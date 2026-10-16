import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/core/widgets/senior_bottom_nav.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/guardian_home_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_data.dart';
import 'package:alkong_yakong/features/guardian/application/guardians_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MvpSession.userId = '';
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'guardian pharmacist back returns to preceding tab at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              careOverviewProvider.overrideWith(
                (ref) async => const CareOverview(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.build(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const GuardianHomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final nav = find.byType(SeniorBottomNav);
        Finder tab(String name) =>
            find.descendant(of: nav, matching: find.text(name));
        int index() => tester.widget<SeniorBottomNav>(nav).currentIndex;
        await tester.tap(tab('AI 약사'));
        await tester.pumpAndSettle();
        expect(index(), 1);
        expect(find.byIcon(TablerIcons.chevron_left), findsOneWidget);
        await tester.tap(find.byIcon(TablerIcons.chevron_left));
        await tester.pumpAndSettle();
        expect(index(), 0);
        await tester.tap(tab('설정'));
        await tester.pumpAndSettle();
        await tester.tap(tab('AI 약사'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(TablerIcons.chevron_left));
        await tester.pumpAndSettle();
        expect(index(), 2);
        await tester.tap(tab('AI 약사'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(index(), 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
