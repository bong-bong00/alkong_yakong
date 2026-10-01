import 'package:alkong_yakong/features/biosignal/application/heart_sensor.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'polar_save_flow_test.dart' show Rig;

void main() {
  for (final zero in [false, true]) {
    test('brief invalid signal recovers without reconnect: zero=$zero', () {
      fakeAsync((clock) {
        final rig = Rig();
        rig.start(clock);
        rig.baseline(clock);
        rig.sdk.sample(zero ? 0 : 62, contactStatus: zero);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 1400));
        expect(rig.sensor.status, HeartSensorStatus.streaming);
        expect(rig.sensor.bpm, isNull);
        expect(rig.api.requests, isEmpty);
        rig.sdk.sample(65);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 200));
        expect(rig.sensor.status, HeartSensorStatus.streaming);
        expect(rig.sensor.bpm, 65);
        expect(rig.sdk.connections, 1);
        expect(rig.sdk.subscriptions, 1);
        rig.window(clock);
        expect(rig.api.requests, hasLength(1));
        rig.api.succeed(0);
        clock.flushMicrotasks();
        rig.sensor.dispose();
        clock.flushMicrotasks();
      });
    });
  }

  test('repeated contact-loss packets do not postpone grace deadline', () {
    fakeAsync((clock) {
      final rig = Rig();
      rig.start(clock);
      rig.baseline(clock);
      for (var i = 0; i < 3; i++) {
        rig.sdk.sample(62, contactStatus: false);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 500));
      }
      clock.flushMicrotasks();
      expect(rig.sensor.status, HeartSensorStatus.failed);
      expect(rig.api.requests, isEmpty);
      rig.sensor.dispose();
      clock.flushMicrotasks();
    });
  });

  test('contact loss near save boundary cannot save old average', () {
    fakeAsync((clock) {
      final rig = Rig();
      rig.start(clock);
      rig.baseline(clock);
      for (var i = 0; i < 29; i++) {
        rig.sdk.sample(65);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
      }
      rig.sdk.sample(65, contactStatus: false);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 2));
      clock.flushMicrotasks();
      expect(rig.sensor.status, HeartSensorStatus.failed);
      expect(rig.api.requests, isEmpty);
      rig.sensor.dispose();
      clock.flushMicrotasks();
    });
  });
}
