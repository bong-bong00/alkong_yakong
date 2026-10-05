import 'package:alkong_yakong/features/biosignal/domain/heart_data.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/monthly_heart_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'heart_records_flow_test.dart' show monthlyData;

void main() {
  testWidgets(
    'stored range labels preserve compact bars and have no demo block',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final readings = <HeartReading>[
        for (final entry in [(1, 48), (2, 60), (3, 100), (4, 125)])
          HeartReading(
            id: entry.$1,
            bpm: entry.$2,
            measuredAt: DateTime(2026, 9, entry.$1),
            measurementContext: HeartMeasurementContext.beforeMedication,
          ),
      ];
      final data = monthlyData(readings);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: MonthlyHeartScreen(data: data, now: DateTime(2026, 9, 28)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('daily-heart-bars')), findsOneWidget);
      expect(find.byKey(const Key('demo-daily-heart-bars')), findsNothing);
      expect(find.textContaining('시연 예시'), findsNothing);
      expect(find.byKey(const Key('heart-bar-value-48')), findsOneWidget);
      expect(find.byKey(const Key('heart-bar-value-125')), findsOneWidget);
      expect(find.byKey(const Key('heart-bar-value-60')), findsNothing);
      expect(find.byKey(const Key('heart-bar-value-100')), findsNothing);
      final label = find.byKey(const Key('heart-bar-value-48'));
      final labelSizer = find
          .ancestor(of: label, matching: find.byType(SizedBox))
          .first;
      expect(tester.getSize(labelSizer).width, 16);
      final daySemantics = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == '1일 복약 전 48 복약 후 없음',
      );
      expect(tester.getSize(daySemantics).width, 44);
      expect(data.readings.length, 4);
      expect(tester.takeException(), isNull);
    },
  );
}
