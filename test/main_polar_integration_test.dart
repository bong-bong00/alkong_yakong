import 'dart:async';

import 'package:alkong_yakong/core/polar_pharmacist_ui/widgets/senior_header.dart';
import 'package:alkong_yakong/dev_mock.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_data.dart';
import 'package:alkong_yakong/features/biosignal/application/heart_sensor.dart';
import 'package:alkong_yakong/features/medication/application/medication_controller.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/measure_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/saved_screen.dart';
import 'package:alkong_yakong/features/easy_flow/presentation/easy_dose_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:polar/polar.dart';

import 'polar_save_flow_test.dart' show Rig, FakePolar;

class _FlowMedication extends MedicationController {
  @override
  TodayMedication build() => const TodayMedication(
    doses: [
      DoseEntry(
        slot: DoseSlot.dinner,
        medicines: [Medicine(ingredient: '시험약정', amount: '1알')],
      ),
    ],
    guardianRelation: '보호자',
    guardianName: '가족',
  );

  @override
  Future<DoseCheckOutcome> take(DoseSlot slot, {DateTime? now}) async {
    state = TodayMedication(
      doses: [
        state.doseOf(slot).copyWith(taken: true, takenAt: DateTime.now()),
      ],
      guardianRelation: '보호자',
      guardianName: '가족',
    );
    return DoseCheckOutcome.recorded;
  }
}

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
        final permission = Completer<bool>();
        final rig = Rig(requestPermissions: () => permission.future);
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
        await tester.tap(find.text('다 착용했어요'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(MeasureScreen), findsOneWidget);
        expect(rig.sensor.status, HeartSensorStatus.connecting);
        expect(rig.sdk.searches, 0);
        permission.complete(true);
        await tester.pump();
        await tester.pump();
        expect(rig.sensor.status, HeartSensorStatus.streaming);
        rig.sdk.sample(61);
        await tester.pump();
        expect(rig.sensor.bpm, 61);
        expect(
          tester
              .widget<MeasureScreen>(find.byType(MeasureScreen))
              .measurementContext,
          HeartMeasurementContext.beforeMedication,
        );
        if (cancel) {
          await tester.tap(find.byType(SeniorBackButton));
          await tester.pumpAndSettle();
          expect(find.text('착용해 주세요'), findsOneWidget);
          expect(rig.api.requests, isEmpty);
        } else {
          await rig.widgetWindow(tester);
          expect(rig.api.requests.length, 1);
          rig.api.succeed(0);
          await tester.pump();
          await tester.pump();
          await tester.pumpAndSettle();
          expect(find.byType(SavedScreen), findsNothing);
          expect(find.byType(MeasureScreen), findsNothing);
          expect(find.text('잘 측정했어요'), findsOneWidget);
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

  for (final disconnect in [false, true]) {
    testWidgets(
      'easy flow measures and saves before and after medication, disconnect=$disconnect',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(480, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final permission = Completer<bool>();
        final rig = Rig(requestPermissions: () => permission.future);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [medicationProvider.overrideWith(_FlowMedication.new)],
            child: MaterialApp(
              home: Scaffold(body: EasyDoseFlow(sensor: rig.sensor)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('복약 전 심박 측정'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('다 착용했어요'));
        await tester.pump(const Duration(milliseconds: 400));
        permission.complete(true);
        await tester.pump();
        await tester.pump();
        expect(rig.sensor.status, HeartSensorStatus.streaming);
        Future<void> finishWindow(int index, String context) async {
          await rig.widgetWindow(tester);
          expect(rig.api.requests.length, index + 1);
          expect(rig.api.requests[index]['measurement_context'], context);
          rig.api.succeed(index);
          await tester.pump();
          await tester.pump();
          await tester.pumpAndSettle();
          expect(find.byType(SavedScreen), findsNothing);
        }

        await finishWindow(0, 'before_medication');
        expect(find.text('4 / 8'), findsOneWidget);
        expect(find.bySemanticsLabel('성인이 쉴 때의 기준이에요.'), findsOneWidget);
        await tester.tap(find.text('이제 약 드시기'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('먹었어요'));
        await tester.pumpAndSettle();
        expect(find.text('6 / 8'), findsOneWidget);
        expect(find.textContaining('약의 효과를 판정하는 검사는 아니에요'), findsOneWidget);
        if (disconnect) {
          rig.sdk.disconnected.add(
            const PolarDeviceDisconnectedEvent(FakePolar.device, false),
          );
          await tester.pump();
        }
        await tester.tap(find.text('복약 후 심박 측정'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(rig.sensor.status, HeartSensorStatus.streaming);
        expect(
          rig.sensor.measurementContext,
          HeartMeasurementContext.afterMedication,
        );
        await finishWindow(1, 'after_medication');
        expect(find.byType(MeasureScreen), findsNothing);
        expect(find.text('8 / 8'), findsOneWidget);
        expect(find.text('측정값을 비교해요'), findsOneWidget);
        expect(find.text('약이 잘 듣고 있어요'), findsNothing);
        expect(find.textContaining('자동으로 알렸어요'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        rig.sensor.dispose();
        await tester.pump();
      },
    );
  }

  testWidgets(
    'easy flow save failure stays on measurement, never shows result',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final rig = Rig();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [medicationProvider.overrideWith(_FlowMedication.new)],
          child: MaterialApp(
            home: Scaffold(body: EasyDoseFlow(sensor: rig.sensor)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('복약 전 심박 측정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다 착용했어요'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await rig.widgetWindow(tester);
      rig.api.pending.single.complete(<String, dynamic>{});
      await tester.pump();
      await tester.pump();
      expect(find.byType(MeasureScreen), findsOneWidget);
      expect(find.text('저장 여부를 확인하지 못했어요'), findsOneWidget);
      expect(find.text('4 / 8'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      rig.sensor.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'cancel pending connection then reenter measurement completes a fresh connection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(480, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final permission = Completer<bool>();
      final rig = Rig(requestPermissions: () => permission.future);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [medicationProvider.overrideWith(_FlowMedication.new)],
          child: MaterialApp(
            home: Scaffold(body: EasyDoseFlow(sensor: rig.sensor)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('복약 전 심박 측정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다 착용했어요'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.byType(SeniorBackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다 착용했어요'));
      await tester.pump(const Duration(milliseconds: 400));
      permission.complete(true);
      await tester.pump();
      await tester.pump();
      expect(rig.sensor.status, HeartSensorStatus.streaming);
      expect(rig.sdk.connections, 1);
      rig.sdk.sample(63);
      await tester.pump();
      expect(rig.sensor.bpm, 63);
      expect(rig.api.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
      rig.sensor.dispose();
      await tester.pump();
    },
  );
}
