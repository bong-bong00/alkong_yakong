import 'dart:async';

import 'package:alkong_yakong/features/biosignal/application/heart_sensor.dart';
import 'package:alkong_yakong/features/biosignal/data/polar_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/measure_screen.dart';
import 'package:polar/polar.dart';

import 'polar_save_flow_test.dart' show FakePolar, Rig;

PolarDeviceInfo device(String name, String id, {bool connectable = true}) =>
    PolarDeviceInfo(
      deviceId: id,
      address: '',
      rssi: -40,
      name: name,
      isConnectable: connectable,
    );

void main() {
  for (final name in ['Polar Sense ABC12345', 'Polar Verity Sense ABC12345']) {
    test(
      'actual advertised name $name connects through sensor start',
      () async {
        final rig = Rig();
        rig.sdk.searchOverride = () => Stream.value(device(name, 'ABC12345'));
        await rig.sensor.start();
        expect(rig.sensor.status, HeartSensorStatus.streaming);
        expect(rig.sdk.connections, 1);
        expect(rig.sdk.subscriptions, 1);
        rig.sensor.dispose();
      },
    );
  }

  test('timeout cancels native scan before retry', () async {
    final sdk = FakePolar();
    var cancelled = false;
    final scan = StreamController<PolarDeviceInfo>(
      onCancel: () {
        cancelled = true;
      },
    );
    sdk.searchOverride = () => scan.stream;
    final service = PolarService(polar: sdk);
    await expectLater(
      service.findDeviceId(
        targetName: 'Polar Verity Sense',
        targetDeviceId: 'known',
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled, isTrue);
    sdk.searchOverride = () =>
        Stream.value(device('Polar Sense known', 'known'));
    expect(
      await service.findDeviceId(
        targetName: 'Polar Verity Sense',
        targetDeviceId: 'known',
      ),
      'known',
    );
    await scan.close();
    await service.dispose();
  });

  test('known device retry never switches to another Sense', () async {
    final sdk = FakePolar();
    sdk.searchOverride = () => Stream.fromIterable([
      device('Polar Sense other', 'other'),
      device('Renamed sensor', 'known'),
    ]);
    final service = PolarService(polar: sdk);
    expect(
      await service.findDeviceId(
        targetName: 'Polar Verity Sense',
        targetDeviceId: 'known',
        allowNameFallback: false,
      ),
      'known',
    );
    await service.dispose();
  });

  test('unrelated and non-connectable advertisements are ignored', () async {
    final sdk = FakePolar();
    sdk.searchOverride = () => Stream.fromIterable([
      device('Polar H10 other', 'other'),
      device('Polar Sense busy', 'busy', connectable: false),
      device('Polar Sense ready', 'ready'),
    ]);
    final service = PolarService(polar: sdk);
    expect(
      await service.findDeviceId(
        targetName: 'Polar Verity Sense',
        targetDeviceId: 'known',
      ),
      'ready',
    );
    await service.dispose();
  });

  test('native scan failure can retry all the way to HR stream', () async {
    final rig = Rig();
    rig.sdk.searchOverride = () =>
        Stream.error(PlatformException(code: 'scan_failed'));
    await rig.sensor.start();
    expect(rig.sensor.status, HeartSensorStatus.failed);
    await rig.sensor.connectionSettled;
    rig.sdk.searchOverride = () =>
        Stream.value(device('Polar Sense ABC12345', 'ABC12345'));
    await rig.sensor.start();
    expect(rig.sensor.status, HeartSensorStatus.streaming);
    expect(rig.sdk.searches, 2);
    expect(rig.sdk.subscriptions, 1);
    rig.sensor.dispose();
  });

  test('scan ending without target is not reported as connected', () async {
    final rig = Rig();
    rig.sdk.searchOverride = () =>
        Stream.value(device('Other sensor', 'other'));
    await rig.sensor.start();
    expect(rig.sensor.status, HeartSensorStatus.failed);
    expect(rig.sdk.connections, 0);
    expect(rig.sdk.subscriptions, 0);
    rig.sensor.dispose();
  });

  testWidgets('recovery button retries failed search and receives live HR', (
    tester,
  ) async {
    final rig = Rig();
    rig.sdk.searchOverride = () =>
        Stream.error(PlatformException(code: 'scan_failed'));
    await tester.pumpWidget(
      MaterialApp(home: MeasureScreen(sensor: rig.sensor)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('다시 연결하기'), findsOneWidget);
    rig.sdk.searchOverride = () =>
        Stream.value(device('Polar Sense ABC12345', 'ABC12345'));
    await tester.tap(find.text('다시 연결하기'));
    await tester.pump();
    await tester.pump();
    expect(rig.sensor.status, HeartSensorStatus.streaming);
    rig.sdk.sample(65);
    await tester.pump();
    expect(rig.sensor.bpm, 65);
    expect(rig.sdk.searches, 2);
    await tester.pumpWidget(const SizedBox());
    rig.sensor.dispose();
  });
}
