import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/widgets/senior_header.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_data.dart';
import 'package:alkong_yakong/features/guardian/application/guardians_provider.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/guardian_prescription_screen.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/add_medicine_screen.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/manual_medicine_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MvpSession.userId = 'guardian';
  });
  testWidgets(
    'patient selection opens three registration methods, camera can go back',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            careOverviewProvider.overrideWith(
              (ref) async => const CareOverview(
                patients: [
                  CarePatient(
                    linkId: 'link',
                    patientId: 'patient',
                    name: '시연 사용자',
                  ),
                ],
              ),
            ),
          ],
          child: const MaterialApp(home: GuardianPickPatientScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('시연 사용자'));
      await tester.pumpAndSettle();
      expect(find.byType(AddMedicineScreen), findsOneWidget);
      expect(find.text('처방전 대신 등록'), findsOneWidget);
      expect(find.text('시연 사용자 님의 약으로 등록해요'), findsOneWidget);
      expect(find.text('카메라 촬영'), findsOneWidget);
      expect(find.text('앨범에서 고르기'), findsOneWidget);
      expect(find.text('직접 작성'), findsOneWidget);
      expect(find.text('가족에게 부탁하기'), findsNothing);
      await tester.tap(find.text('카메라 촬영'));
      await tester.pumpAndSettle();
      expect(find.byType(AddMedicineScreen), findsNothing);
      await tester.tap(find.byType(SeniorBackButton));
      await tester.pumpAndSettle();
      expect(find.byType(AddMedicineScreen), findsOneWidget);
      await tester.tap(find.text('직접 작성'));
      await tester.pumpAndSettle();
      final manual = tester.widget<ManualMedicineScreen>(
        find.byType(ManualMedicineScreen),
      );
      expect(manual.onBehalfOfUserId, 'patient');
      expect(manual.onBehalfOf, '시연 사용자');
      await tester.tap(find.byType(SeniorBackButton));
      await tester.pumpAndSettle();
      expect(find.byType(AddMedicineScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual guardian registration writes patient ID without changing guardian session',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, dynamic>? submitted;
      Map<String, dynamic>? saved;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'registered': true,
              'prescription_id': 'patient-rx',
              'dur_result': {
                'analysis_complete': true,
                'has_risk': false,
                'assessment_status': 'SAFE',
                'matches': [],
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'items': [
              {'medicine_code': 'test-code', 'display_name': '테스트약'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: ManualMedicineScreen(
                onBehalfOfUserId: 'patient',
                onBehalfOf: '시연 사용자',
                onSaved: (value) => saved = value,
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField).first, '테스트');
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pumpAndSettle();
        await tester.tap(find.text('테스트약'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('아침'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('이 약 등록하기'));
        await tester.tap(find.text('이 약 등록하기'));
        await tester.pumpAndSettle();
        expect(submitted?['user_id'], 'patient');
        expect(saved?['assessment_status'], 'SAFE');
        expect(MvpSession.userId, 'guardian');
        expect(tester.takeException(), isNull);
      }, () => client);
    },
  );
}
