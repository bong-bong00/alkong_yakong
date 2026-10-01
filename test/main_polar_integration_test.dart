import 'package:alkong_yakong/core/polar_pharmacist_ui/widgets/senior_header.dart';
import 'package:alkong_yakong/dev_mock.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_data.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/measure_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/saved_screen.dart';
import 'package:alkong_yakong/features/easy_flow/presentation/easy_dose_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'polar_save_flow_test.dart' show Rig;

void main() {
  for (final cancel in [true, false]) {
    testWidgets(
      'main easy flow uses Polar measurement and ${cancel ? "cancels" : "returns after saving"}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(480, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final rig = Rig();
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  Scaffold(body: EasyDoseFlow(sensor: rig.sensor)),
            ),
            GoRoute(
              path: '/biosignal',
              builder: (_, _) =>
                  const Scaffold(body: Text('unexpected heart redirect')),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: devMockOverrides(force: true),
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('복약 전 심박 측정'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('다 찼어요'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(MeasureScreen), findsOneWidget);
        expect(
          tester
              .widget<MeasureScreen>(find.byType(MeasureScreen))
              .measurementContext,
          HeartMeasurementContext.beforeMedication,
        );
        if (cancel) {
          await tester.tap(find.byType(SeniorBackButton));
          await tester.pumpAndSettle();
          expect(find.text('차 주세요'), findsOneWidget);
          expect(rig.api.requests, isEmpty);
        } else {
          await rig.widgetWindow(tester);
          expect(rig.api.requests.length, 1);
          rig.api.succeed(0);
          await tester.pump();
          await tester.pump();
          await tester.ensureVisible(find.text('저장된 기록 확인하기'));
          await tester.tap(find.text('저장된 기록 확인하기'));
          await tester.pumpAndSettle();
          expect(find.byType(SavedScreen), findsOneWidget);
          await tester.tap(find.text('확인했어요'));
          await tester.pumpAndSettle();
          expect(find.byType(MeasureScreen), findsNothing);
          expect(find.text('잘 쟀어요'), findsOneWidget);
        }
        expect(find.text('unexpected heart redirect'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        rig.sensor.dispose();
        router.dispose();
        await tester.pump();
      },
    );
  }
}
