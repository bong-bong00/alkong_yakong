import 'dart:convert';
import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/session/presentation_history.dart';
import 'package:alkong_yakong/features/medication/application/medication_controller.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:alkong_yakong/features/medication/domain/presentation_medication.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final demoDay = DateTime(2026, 10, 6, 14);
  setUp(() {
    final original = MvpSession.userId;
    addTearDown(() => MvpSession.userId = original);
    MvpSession.userId = PresentationHistory.userId;
  });

  test(
    'only presentation morning/lunch flags change; data and dinner survive',
    () {
      const medicine = Medicine(
        ingredient: '코다론정',
        amount: '1알',
        scheduleId: 123,
      );
      final server = TodayMedication(
        doses: [
          const DoseEntry(slot: DoseSlot.morning, medicines: [medicine]),
          DoseEntry(
            slot: DoseSlot.lunch,
            medicines: const [medicine],
            taken: true,
            takenAt: demoDay,
          ),
          const DoseEntry(slot: DoseSlot.dinner, medicines: [medicine]),
        ],
        guardianName: '가족',
        guardianRelation: '보호자',
        heartRate: 98,
        daysLeft: 6,
      );
      final prepared = preparePresentationMedication(
        server,
        userId: PresentationHistory.userId,
        now: demoDay,
        lunchTaken: false,
      );
      expect(prepared.doseOf(DoseSlot.morning).taken, isTrue);
      expect(prepared.doseOf(DoseSlot.lunch).taken, isFalse);
      expect(prepared.doseOf(DoseSlot.lunch).takenAt, isNull);
      expect(
        prepared.doseOf(DoseSlot.lunch).medicines,
        same(server.doseOf(DoseSlot.lunch).medicines),
      );
      expect(
        prepared.doseOf(DoseSlot.dinner),
        same(server.doseOf(DoseSlot.dinner)),
      );
      expect(prepared.heartRate, 98);
      expect(prepared.daysLeft, 6);
      expect(server.doseOf(DoseSlot.lunch).taken, isTrue);
      for (final (userId, day) in [
        ('other-user', demoDay),
        (PresentationHistory.userId, DateTime(2026, 10, 7)),
        (PresentationHistory.userId, DateTime(2025, 10, 6)),
      ]) {
        expect(
          preparePresentationMedication(
            server,
            userId: userId,
            now: day,
            lunchTaken: false,
          ),
          same(server),
        );
      }
    },
  );

  for (final failedSave in [false, true]) {
    test(
      'demo completion failed=$failedSave: no initialization writes; refresh preserves button result',
      () async {
        final posts = <Map<String, dynamic>>[];
        final client = MockClient((request) async {
          if (request.method == 'POST') {
            posts.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              failedSave ? '{}' : '{"status":"TAKEN","duplicate":true}',
              failedSave ? 500 : 200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'doses': [
                for (final (slot, id, taken) in [
                  ('morning', 1, false),
                  ('lunch', 2, true),
                  ('dinner', 3, false),
                ])
                  {
                    'slot': slot,
                    'taken': taken,
                    'medicines': [
                      {
                        'medicine_code': '200701021',
                        'product_name': '코다론정',
                        'schedule_id': id,
                      },
                    ],
                  },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final container = ProviderContainer(
          overrides: [
            medicationProvider.overrideWith(
              () => MedicationController(
                apiClient: ApiClient(client: client),
                now: () => demoDay,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(medicationProvider.notifier);
        await Future<void>.delayed(Duration.zero);
        await controller.refreshFromServer();
        expect(posts, isEmpty);
        expect(
          container.read(medicationProvider).doseOf(DoseSlot.morning).taken,
          isTrue,
        );
        expect(
          container.read(medicationProvider).doseOf(DoseSlot.lunch).taken,
          isFalse,
        );
        if (failedSave) {
          await expectLater(
            controller.take(DoseSlot.lunch, now: demoDay),
            throwsA(isA<ApiException>()),
          );
        } else {
          expect(
            await controller.take(DoseSlot.lunch, now: demoDay),
            DoseCheckOutcome.recorded,
          );
        }
        expect(posts.single['schedule_id'], 2);
        await controller.refreshFromServer();
        expect(
          container.read(medicationProvider).doseOf(DoseSlot.lunch).taken,
          !failedSave,
        );
        expect(
          container.read(medicationProvider).doseOf(DoseSlot.dinner).taken,
          isFalse,
        );
      },
    );
  }
}
