import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_home_screen.dart';
import 'package:alkong_yakong/features/medication/application/medication_controller.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/features/profile/application/current_user_controller.dart';
import 'package:alkong_yakong/features/profile/domain/user_profile.dart';
import 'package:alkong_yakong/features/medicines/application/user_medicines_controller.dart';
import 'package:alkong_yakong/features/medicines/domain/user_medicine_models.dart';
import 'package:alkong_yakong/features/guardian/application/guardians_provider.dart';

class _StatusMedicationController extends MedicationController {
  _StatusMedicationController(this.status);
  final MedicationFetchStatus status;

  @override
  TodayMedication build() => TodayMedication(
    doses: const [],
    guardianRelation: '보호자',
    guardianName: '가족',
    fetchStatus: status,
  );
}

class _ArrivedTestUser extends CurrentUserController {
  @override
  Future<UserProfile?> build() async => UserProfile.fromJson({
    'id': 'arrived-test-user',
    'name': '테스트',
    'role': 'patient',
  });
}

class _ArrivedTestMedicines extends UserMedicinesController {
  @override
  Future<List<UserMedicine>> build() async => [
    UserMedicine.fromJson({
      'medicine_code': 'NEW-CODE',
      'product_name': '코다론정',
    }),
  ];
}

void main() {
  testWidgets('홈 진입과 재진입은 새 약 코드가 있어도 약 도착 화면을 띄우지 않는다', (tester) async {
    MvpSession.userId = 'arrived-test-user';
    SharedPreferences.setMockInitialValues({
      'family_inbox_seen_arrived-test-user': ['OLD-CODE'],
    });
    final container = ProviderContainer(
      overrides: [
        medicationProvider.overrideWith(
          () => _StatusMedicationController(MedicationFetchStatus.ready),
        ),
        currentUserProvider.overrideWith(_ArrivedTestUser.new),
        userMedicinesProvider.overrideWith(_ArrivedTestMedicines.new),
        guardiansProvider.overrideWith((ref) async => []),
      ],
    );
    addTearDown(container.dispose);
    await container.read(currentUserProvider.future);
    await container.read(userMedicinesProvider.future);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, state) =>
              Scaffold(body: PatientHomeScreen(key: ValueKey(state.uri.query))),
        ),
        GoRoute(
          path: '/medicine-arrived',
          builder: (_, _) => const Scaffold(body: Text('잘못된 약 도착 화면')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PatientHomeScreen), findsOneWidget);
    expect(find.text('잘못된 약 도착 화면'), findsNothing);
    router.go('/?return=measurement');
    await tester.pumpAndSettle();
    expect(find.byType(PatientHomeScreen), findsOneWidget);
    expect(find.text('잘못된 약 도착 화면'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final status in MedicationFetchStatus.values) {
    testWidgets('오늘 홈은 $status 상태를 약 없음으로 오인하지 않는다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            medicationProvider.overrideWith(
              () => _StatusMedicationController(status),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: PatientHomeScreen())),
        ),
      );
      await tester.pump();

      expect(
        find.text('등록된 약이 없어요'),
        status == MedicationFetchStatus.ready ? findsOneWidget : findsNothing,
      );
      if (status == MedicationFetchStatus.failed) {
        expect(find.text('다시 시도'), findsOneWidget);
      }
    });
  }
}
