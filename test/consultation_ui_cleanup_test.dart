import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_data.dart';
import 'package:alkong_yakong/features/guardian/application/guardians_provider.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/guardian_pharmacist_screen.dart';
import 'package:alkong_yakong/features/guardian/presentation/widgets/add_care_sheet.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/add_medicine_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MvpSession.userId = '';
  });
  testWidgets('missing patient actions are compact outlined buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          careOverviewProvider.overrideWith(
            (ref) async => const CareOverview(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: const GuardianPharmacistScreen(initialPatientId: 'removed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['다시 확인', '일반 약 상담하기']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byType(OutlinedButton),
      );
      expect(button, findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(button)
            .style!
            .textStyle!
            .resolve({})!
            .fontSize,
        16,
      );
      expect(tester.getSize(button).height, lessThanOrEqualTo(56));
    }
    await tester.tap(find.text('일반 약 상담하기'));
    await tester.pumpAndSettle();
    expect(find.text('일반 약 상담'), findsOneWidget);
    expect(find.textContaining('환자 연결을 확인하지'), findsNothing);
  });
  testWidgets('add care back dismisses without returning an invitation', (
    tester,
  ) async {
    PendingInvite? result;
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showAddCareSheet(context);
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('돌보는 분 추가하기'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
    expect(find.text('돌보는 분 추가하기'), findsNothing);
  });
  testWidgets('registration title uses the same weight for both words', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AddMedicineScreen(onPick: (_) {})),
    );
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(
      find.byWidgetPredicate(
        (w) => w is Text && w.textSpan?.toPlainText() == '어떻게 넣을까요?',
      ),
    );
    final spans = (title.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((s) => s.style!.fontWeight).toSet(), {FontWeight.w500});
  });
}
