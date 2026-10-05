import 'package:alkong_yakong/core/session/presentation_history.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_data.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/monthly_heart_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'heart_records_flow_test.dart' show monthlyData;

void main() {
  testWidgets('dedicated demo graph is separate from real records', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MonthlyHeartScreen(
          data: monthlyData(const []),
          now: DateTime(2026, 10, 6),
          userId: PresentationHistory.userId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('daily-heart-bars')), findsOneWidget);
    expect(find.byKey(const Key('demo-daily-heart-bars')), findsOneWidget);
    expect(find.text('가상 데이터 · 실제 측정 아님'), findsOneWidget);
    for (final value in [48, 54, 104, 125, 118]) {
      expect(find.byKey(Key('heart-bar-value-$value')), findsOneWidget);
    }
    expect(find.byKey(const Key('heart-bar-value-76')), findsNothing);
    expect(find.text('저장된 심박 기록'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ordinary records show only out-of-range labels, including at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final readings = <HeartReading>[
        for (final value in [48, 60, 100, 125])
          HeartReading(
            id: value,
            bpm: value,
            measuredAt: DateTime(
              2026,
              9,
              value == 48
                  ? 1
                  : value == 60
                  ? 2
                  : value == 100
                  ? 3
                  : 4,
            ),
            measurementContext: HeartMeasurementContext.beforeMedication,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: MonthlyHeartScreen(
              data: monthlyData(readings),
              now: DateTime(2026, 9, 28),
              userId: 'ordinary',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('demo-daily-heart-bars')), findsNothing);
      expect(find.byKey(const Key('heart-bar-value-48')), findsOneWidget);
      expect(find.byKey(const Key('heart-bar-value-125')), findsOneWidget);
      expect(find.byKey(const Key('heart-bar-value-60')), findsNothing);
      expect(find.byKey(const Key('heart-bar-value-100')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
