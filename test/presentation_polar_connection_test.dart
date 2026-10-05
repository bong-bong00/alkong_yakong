import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/dev_mock.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/home_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_home_screen.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:alkong_yakong/features/biosignal/application/heart_device.dart';
import 'package:alkong_yakong/features/biosignal/data/heart_repository.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_data.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/measure_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/polar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'polar_save_flow_test.dart' show Rig;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'heart.paired': true});
    MvpSession.userId = 'presentation-test';
  });

  for (final before in [true, false]) {
    testWidgets(
      'home ${before ? "before" : "after"} measurement after normal measurement saves purpose and returns BPM',
      (tester) async {
        final rig = Rig();
        await rig.sensor.start();
        await rig.widgetWindow(tester);
        rig.api.succeed(0);
        await tester.pump();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...devMockOverrides(force: true),
              heartSensorProvider.overrideWithValue(rig.sensor),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );
        // Home has a repeating pulse animation; settling is intentionally impossible.
        await tester.pump(const Duration(milliseconds: 400));
        final home = tester.widget<PatientHomeScreen>(
          find.byType(PatientHomeScreen),
        );
        final result = before
            ? home.onMeasureBefore!(DoseSlot.dinner)
            : home.onMeasure!(DoseSlot.dinner);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.widget<MeasureScreen>(find.byType(MeasureScreen)).sensor,
          same(rig.sensor),
        );
        expect(rig.sdk.connections, 1);
        await rig.widgetWindow(tester);
        expect(
          rig.api.requests.last['measurement_context'],
          before ? 'before_medication' : 'after_medication',
        );
        rig.api.succeed(1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(find.text('저장된 기록 확인하기'));
        await tester.tap(find.text('저장된 기록 확인하기'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final confirm = find.text(before ? '이제 약 먹으러 가기' : '확인했어요');
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(await result, 82);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(MeasureScreen), findsNothing);
        expect(rig.sdk.connections, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        rig.sensor.dispose();
        await tester.pump();
      },
    );
  }

  testWidgets(
    'normal measurement then another screen reuses the connected sensor',
    (tester) async {
      final rig = Rig();
      await rig.sensor.start(measure: false);
      final repository = HeartRepository(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              '{"today":{},"week":[],"month":[],"readings":[]}',
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [heartSensorProvider.overrideWithValue(rig.sensor)],
          child: MaterialApp(home: HeartScreen(repository: repository)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('연결 확인 후 측정'));
      await tester.tap(find.text('연결 확인 후 측정'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MeasureScreen), findsOneWidget);
      expect(
        tester.widget<MeasureScreen>(find.byType(MeasureScreen)).sensor,
        same(rig.sensor),
      );
      expect(rig.sdk.searches, 1);
      expect(rig.sdk.connections, 1);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('연결 확인 후 측정'));
      await tester.tap(find.text('연결 확인 후 측정'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MeasureScreen), findsOneWidget);
      expect(rig.sdk.connections, 1);
      await tester.pumpWidget(const SizedBox());
      rig.sensor.dispose();
      await tester.pump();
    },
  );

  testWidgets('device search only connects and does not save a measurement', (
    tester,
  ) async {
    final rig = Rig();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [heartSensorProvider.overrideWithValue(rig.sensor)],
        child: const MaterialApp(home: PolarScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('기기 찾기'));
    await tester.tap(find.text('기기 찾기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await rig.widgetWindow(tester);
    expect(rig.api.requests, isEmpty);
    expect(rig.sensor.measuring, isFalse);
    await tester.pumpWidget(const SizedBox());
    rig.sensor.dispose();
    await tester.pump();
  });
}
