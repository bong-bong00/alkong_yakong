import 'package:alkong_yakong/features/reminder/application/alarm_preferences.dart';
import 'package:alkong_yakong/features/reminder/application/reminder_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class _FakeNotifications extends ReminderNotifications {
  final synced = <AlarmPreferences>[];

  @override
  Future<void> sync(AlarmPreferences prefs) async => synced.add(prefs);
}

void main() {
  group('ReminderPlan.forPrefs', () {
    test('자동 알림을 끄면 아무것도 예약하지 않는다', () {
      expect(
        ReminderPlan.forPrefs(const AlarmPreferences(autoAlarm: false)),
        isEmpty,
      );
    });

    test('켜면 아침·저녁 두 개를 정시에 예약한다', () {
      final plan = ReminderPlan.forPrefs(
        const AlarmPreferences(
          repeatOnce: false,
          morningHour: 8,
          eveningHour: 18,
        ),
      );

      expect(plan.map((r) => r.id), [
        ReminderPlan.morningId,
        ReminderPlan.eveningId,
      ]);
      expect([plan[0].hour, plan[0].minute], [8, 0]);
      expect([plan[1].hour, plan[1].minute], [18, 0]);
      expect(plan[0].title, '약 드실 시간이에요');
      expect(plan[0].body, '아침 8시 약을 물과 함께 드세요.');
      expect(plan[1].body, '저녁 6시 약을 물과 함께 드세요.');
    });

    test('10분 뒤 한 번 더를 켜면 네 개, 다시 알림은 10분 뒤', () {
      final plan = ReminderPlan.forPrefs(
        const AlarmPreferences(morningHour: 7, eveningHour: 20),
      );
      final byId = {for (final r in plan) r.id: r};

      expect(plan, hasLength(4));
      expect(byId.keys.toSet(), ReminderPlan.allIds.toSet());
      expect(
        [
          byId[ReminderPlan.morningId]!.hour,
          byId[ReminderPlan.morningId]!.minute,
        ],
        [7, 0],
      );
      expect(
        [
          byId[ReminderPlan.eveningId]!.hour,
          byId[ReminderPlan.eveningId]!.minute,
        ],
        [20, 0],
      );

      final morningAgain = byId[ReminderPlan.morningFollowUpId]!;
      final eveningAgain = byId[ReminderPlan.eveningFollowUpId]!;
      expect([morningAgain.hour, morningAgain.minute], [7, 10]);
      expect([eveningAgain.hour, eveningAgain.minute], [20, 10]);
      expect(morningAgain.body, contains('아직 안 드셨다면 지금 드세요.'));
      expect(eveningAgain.body, startsWith('저녁 8시'));
    });
  });

  group('ReminderPlan.nextInstance', () {
    late tz.Location seoul;
    const morning = PlannedReminder(
      id: ReminderPlan.morningId,
      hour: 8,
      minute: 0,
      title: '',
      body: '',
    );

    setUpAll(() {
      tz_data.initializeTimeZones();
      seoul = tz.getLocation('Asia/Seoul');
    });

    test('아직 안 된 시각이면 오늘', () {
      final now = tz.TZDateTime(seoul, 2026, 9, 14, 7, 30);
      expect(
        ReminderPlan.nextInstance(morning, now),
        tz.TZDateTime(seoul, 2026, 9, 14, 8),
      );
    });

    test('딱 그 시각이거나 지났으면 내일, 달이 바뀌어도', () {
      expect(
        ReminderPlan.nextInstance(
          morning,
          tz.TZDateTime(seoul, 2026, 9, 14, 8),
        ),
        tz.TZDateTime(seoul, 2026, 9, 15, 8),
      );
      expect(
        ReminderPlan.nextInstance(
          morning,
          tz.TZDateTime(seoul, 2026, 9, 30, 21),
        ),
        tz.TZDateTime(seoul, 2026, 10, 1, 8),
      );
    });
  });

  test('플러그인이 없는 곳에서도 초기화·예약·권한 요청이 터지지 않는다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final notifications = ReminderNotifications();

    await notifications.initialize();
    await notifications.sync(const AlarmPreferences());
    expect(await notifications.requestPermissions(exactAlarm: true), isTrue);
  });

  test('저장된 설정을 읽은 뒤와 바꿀 때마다 알림을 다시 맞춘다', () async {
    SharedPreferences.setMockInitialValues({'alarm.morning': 9});
    final fake = _FakeNotifications();
    final container = ProviderContainer(
      overrides: [reminderNotificationsProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    container.read(alarmPreferencesProvider);
    await pumpEventQueue();
    expect(fake.synced.single.morningHour, 9);

    await container
        .read(alarmPreferencesProvider.notifier)
        .update(const AlarmPreferences(autoAlarm: false));
    expect(fake.synced, hasLength(2));
    expect(fake.synced.last.autoAlarm, isFalse);
  });
}
