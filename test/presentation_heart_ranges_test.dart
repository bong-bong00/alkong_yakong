import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/presentation_history.dart';
import 'package:alkong_yakong/features/biosignal/data/heart_repository.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/heart_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    String id,
    String day, {
    bool failed = false,
  }) async {
    final repository = HeartRepository(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({
              'period_date': day,
              'readings': [],
              'today': {},
              'week': [],
              'month': [],
            }),
            failed ? 503 : 200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: HeartScreen(userId: id, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final day in ['2026-10-05', '2026-10-06']) {
    testWidgets('both ranges remain visible on presentation day $day', (
      tester,
    ) async {
      await open(tester, PresentationHistory.userId, day);
      expect(find.text('오늘 측정'), findsOneWidget);
      expect(find.text('시연 예시 · 실제 측정 아님'), findsOneWidget);
      expect(find.text('평소 심박 측정'), findsNWidgets(2));
      expect(find.text('48회/분'), findsOneWidget);
      expect(find.text('125회/분'), findsOneWidget);
      expect(find.text('느린 범위'), findsOneWidget);
      expect(find.text('빠른 범위'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ordinary account never gets synthetic examples', (tester) async {
    await open(tester, 'ordinary-user', '2026-10-06');
    expect(find.text('시연 예시 · 실제 측정 아님'), findsNothing);
    expect(find.text('48회/분'), findsNothing);
    expect(find.text('아직 측정 기록이 없어요'), findsOneWidget);
  });

  testWidgets('demo examples survive read failure without hiding the failure', (
    tester,
  ) async {
    await open(tester, PresentationHistory.userId, '2026-10-06', failed: true);
    expect(find.text('심박수 기록을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('48회/분'), findsOneWidget);
    expect(find.text('125회/분'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
