import 'dart:convert';
import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/features/biosignal/data/heart_repository.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/widgets/heart_readings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'heart_records_flow_test.dart' show body, wrap;

void main() {
  for (final count in [0, 1, 2, 4]) {
    testWidgets('weekly $count records use latest two and optional expansion', (
      tester,
    ) async {
      final now = DateTime.now();
      final payload = body();
      payload['readings'] = [
        for (var id = 1; id <= count; id++)
          {
            'id': id,
            'bpm': 70 + id,
            'measured_at': DateTime(
              now.year,
              now.month,
              now.day,
              12,
              id,
            ).toUtc().toIso8601String(),
            'measurement_context': 'general',
          },
      ];
      final repository = HeartRepository(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(payload),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );
      await tester.pumpWidget(wrap(HeartScreen(repository: repository)));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('weekly-heart-toggle-readings'));
      if (count == 0) {
        expect(find.byType(HeartReadingsCard), findsNothing);
      } else {
        List<int> shown() => tester
            .widget<HeartReadingsCard>(find.byType(HeartReadingsCard))
            .readings
            .map((r) => r.id)
            .toList();
        expect(shown(), count == 1 ? [1] : [count, count - 1]);
        if (count > 2) {
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(shown(), [4, 3, 2, 1]);
          expect(find.text('접기'), findsOneWidget);
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(shown(), [4, 3]);
        }
      }
      expect(toggle, count > 2 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
