import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_data.dart';
import 'package:alkong_yakong/features/guardian/application/guardians_provider.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/care_manage_screen.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/care_patient_screen.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/guardian_account_screen.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/guardian_alert_prefs_screen.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/guardian_prescription_screen.dart';
import 'package:alkong_yakong/features/medicines/application/user_medicines_controller.dart';
import 'package:alkong_yakong/features/profile/domain/user_profile.dart';
import 'package:alkong_yakong/features/profile/data/user_repository.dart';
import 'package:alkong_yakong/features/profile/application/current_user_controller.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/account_screen.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/help_screen.dart';

class CountingUsers extends UserRepository {
  int deletions = 0;
  @override
  Future<void> delete(String userId) async {
    deletions++;
  }

  @override
  Future<UserProfile> fetch(String id) async =>
      UserProfile(id: id, name: '보호자', role: 'guardian');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MvpSession.userId = 'g';
  });
  testWidgets('dismissing withdrawal confirmation never deletes account', (
    tester,
  ) async {
    final users = CountingUsers();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userRepositoryProvider.overrideWithValue(users)],
        child: const MaterialApp(home: AccountScreen(isGuardian: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('탈퇴').last);
    await tester.tap(find.text('탈퇴').last);
    await tester.pumpAndSettle();
    expect(find.text('정말 탈퇴하시겠어요?'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(users.deletions, 0);
    expect(find.text('정말 탈퇴하시겠어요?'), findsNothing);
  });
  testWidgets(
    'management unlink requires explicit confirmation and refreshes list',
    (tester) async {
      var deletions = 0;
      var linked = true;
      final client = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/api/v1/guardians/link');
        deletions++;
        linked = false;
        return http.Response('', 204);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              careOverviewProvider.overrideWith(
                (ref) async => CareOverview(
                  patients: linked
                      ? [
                          const CarePatient(
                            linkId: 'link',
                            patientId: 'p',
                            name: '환자',
                          ),
                        ]
                      : [],
                ),
              ),
            ],
            child: const MaterialApp(home: CareManageScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('연결 해제'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(deletions, 0);
        await tester.tap(find.text('연결 해제'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('네, 해제할게요'));
        await tester.pumpAndSettle();
        expect(deletions, 1);
        expect(find.text('연결 해제'), findsNothing);
        expect(tester.takeException(), isNull);
      }, () => client);
    },
  );
  test('scheduled dose does not require attention', () {
    final patient = CarePatient.fromJson({
      'link_id': 'l',
      'patient_id': 'p',
      'name': '테스트',
      'next_dose_label': '저녁 약',
      'dose_status': 'scheduled',
      'slots': [
        {'label': '저녁', 'taken': false, 'record_status': 'scheduled'},
      ],
    });
    expect(patient.needsAttention, isFalse);
    expect(patient.slots.single.recordStatus, 'scheduled');
    expect(
      CarePatient.fromJson({
        'dose_status': 'overdue',
        'overdue_dose_label': '아침 약',
      }).needsAttention,
      isTrue,
    );
  });
  for (final screen in [
    const CareManageScreen(),
    const GuardianPickPatientScreen(),
  ]) {
    testWidgets(
      '${screen.runtimeType} shows error rather than empty connection',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              careOverviewProvider.overrideWith(
                (ref) async => throw StateError('offline'),
              ),
            ],
            child: MaterialApp(home: screen),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
        expect(find.text('다시 불러오기'), findsOneWidget);
        expect(find.textContaining('아직 연결된 어르신이 없어요'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets('long patient profile fits narrow screen at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            carePatientProfileProvider.overrideWith(
              (ref, id) async => UserProfile(
                id: id,
                name: '긴 이름 사용자',
                gender: 'F',
                phone: '010-1234-5678',
                bloodType: 'AB',
                heightCm: 155,
                weightKg: 56,
                birthDate: DateTime(1950, 5, 5),
                diseases: const ['길이가 매우 긴 질환 이름을 가진 경우'],
                pastIllnesses: const ['천식', '위궤양', '뇌졸중'],
                familyIllnesses: const ['고혈압', '당뇨'],
                allergies: const ['페니실린'],
                smoking: '안 폈어요',
                drinking: '안 마셔요',
              ),
            ),
            patientMedicinesProvider.overrideWith((ref, id) async => []),
          ],
          child: MaterialApp(
            theme: AppTheme.build(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const CarePatientScreen(
              patient: CarePatient(
                linkId: 'l',
                patientId: 'p',
                name: '긴 이름 사용자',
                age: 76,
                phone: '010-1234-5678',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('기본 정보'), findsOneWidget);
      expect(find.text('병력 · 생활습관'), findsOneWidget);
      expect(find.textContaining('화면이 먼저 알려드려요'), findsNothing);
      await tester.ensureVisible(find.text('담배 · 술'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed alert preference save reverts switch', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GuardianAlertPrefsScreen(
          savePreference: (key, value) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(find.text('설정을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });
  testWidgets(
    'guardian help uses guardian routes and account has no fake password action',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HelpScreen(isGuardian: true, openAll: true)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('설정 → 돌보는 분 관리'), findsWidgets);
      expect(find.textContaining('"내 정보"에서 "센서"'), findsNothing);
      MvpSession.userId = '';
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: GuardianAccountScreen())),
      );
      await tester.pumpAndSettle();
      expect(find.text('비밀번호'), findsNothing);
    },
  );
}
