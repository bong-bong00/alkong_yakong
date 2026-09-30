import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_home_screen.dart';
import 'package:alkong_yakong/features/medication/application/medication_controller.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
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
