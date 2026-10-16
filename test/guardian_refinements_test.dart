import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/widgets/senior_header.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_data.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/guardian_home_screen.dart';
import 'package:alkong_yakong/features/guardian/application/guardian_alert_inbox.dart';
import 'package:alkong_yakong/features/guardian/application/guardians_provider.dart';
import 'package:alkong_yakong/features/guardian/data/alert_repository.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/guardian_info_screen.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/guardian_account_screen.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/account_screen.dart';

class FakeAlerts extends AlertRepository {
  @override
  Future<List<AlertItem>?> fetch(String userId) async => [
    AlertItem(
      id: userId == 'p1' ? 1 : 2,
      type: 'miss',
      title: '미복용 확인',
      desc: userId == 'p1' ? '첫 알림' : '둘째 알림',
      time: '12:00',
    ),
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MvpSession.userId = 'guardian';
  });
  const patients = [
    CarePatient(linkId: 'a', patientId: 'p1', name: '환자하나'),
    CarePatient(linkId: 'b', patientId: 'p2', name: '환자둘'),
  ];

  test(
    'acknowledgement is isolated by guardian and patient and concurrent saves are retained',
    () async {
      final inbox = GuardianAlertInbox('guardian');
      await Future.wait([
        inbox.acknowledge('p1', 1),
        inbox.acknowledge('p1', 2),
      ]);
      expect(await inbox.read('p1'), {1, 2});
      expect(await inbox.read('p2'), isEmpty);
      expect(await GuardianAlertInbox('another').read('p1'), isEmpty);
    },
  );

  testWidgets(
    'confirmed alerts leave unread list and badge but remain in confirmed history',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            careOverviewProvider.overrideWith(
              (ref) async => const CareOverview(patients: patients),
            ),
            guardianAlertRepositoryProvider.overrideWithValue(FakeAlerts()),
          ],
          child: MaterialApp(
            home: GuardianAlertsScreen(
              patient: patients.first,
              patients: patients,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GuardianAlertsScreen)),
      );
      expect(
        await container.read(guardianUnreadCountProvider('guardian').future),
        2,
      );
      expect(find.text('첫 알림'), findsOneWidget);
      await tester.ensureVisible(find.text('확인했어요').first);
      await tester.tap(find.text('확인했어요').first);
      await tester.pumpAndSettle();
      expect(find.text('첫 알림'), findsNothing);
      expect(
        await container.read(guardianUnreadCountProvider('guardian').future),
        1,
      );
      await tester.tap(find.text('확인한 알림 보기'));
      await tester.pumpAndSettle();
      expect(find.text('첫 알림'), findsOneWidget);
      expect(find.text('둘째 알림'), findsNothing);
      expect(find.text('확인했어요'), findsNothing);
      expect(await GuardianAlertInbox('guardian').read('p1'), {1});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account actions are in settings with working back navigation', (
    tester,
  ) async {
    MvpSession.userId = '';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          careOverviewProvider.overrideWith(
            (ref) async => const CareOverview(patients: []),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: GuardianInfoScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('설정'), findsOneWidget);
    expect(find.text('돌보는 분 관리'), findsOneWidget);
    expect(find.text('알림 받는 방법'), findsOneWidget);
    expect(find.text('도움말'), findsOneWidget);
    expect(find.text('약관 · 개인정보'), findsOneWidget);
    await tester.ensureVisible(find.text('로그아웃·탈퇴'));
    await tester.tap(find.text('로그아웃·탈퇴'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AccountScreen>(find.byType(AccountScreen)).isGuardian,
      isTrue,
    );
    await tester.tap(find.byType(SeniorBackButton));
    await tester.pumpAndSettle();
    expect(find.text('설정'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GuardianAccountScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('탈퇴하기'), findsNothing);
    expect(find.text('이 전화기에서 로그아웃'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
