import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reminder_notifications.dart';

/// 복약 알림 설정. 앱을 껐다 켜도 고른 값이 남는다.
@immutable
class AlarmPreferences {
  final bool autoAlarm;
  final bool repeatOnce;
  final bool tellGuardian;

  /// 24시간제. 아침 7~10시, 저녁 17~20시 안에서 고른다.
  final int morningHour;
  final int eveningHour;

  const AlarmPreferences({
    this.autoAlarm = true,
    this.repeatOnce = true,
    this.tellGuardian = true,
    this.morningHour = 8,
    this.eveningHour = 18,
  });

  AlarmPreferences copyWith({
    bool? autoAlarm,
    bool? repeatOnce,
    bool? tellGuardian,
    int? morningHour,
    int? eveningHour,
  }) => AlarmPreferences(
    autoAlarm: autoAlarm ?? this.autoAlarm,
    repeatOnce: repeatOnce ?? this.repeatOnce,
    tellGuardian: tellGuardian ?? this.tellGuardian,
    morningHour: morningHour ?? this.morningHour,
    eveningHour: eveningHour ?? this.eveningHour,
  );

  /// "아침 8시" · "저녁 6시".
  static String spoken(int hour) {
    final display = hour > 12 ? hour - 12 : hour;
    return '${hour >= 12 ? '저녁' : '아침'} $display시';
  }

  /// 내 정보 목록에 쓰는 한 줄.
  String get summary => autoAlarm
      ? '${spoken(morningHour)} · ${spoken(eveningHour)} · 소리로 알려드려요'
      : '소리 알림이 꺼져 있어요';
}

class AlarmPreferencesController extends Notifier<AlarmPreferences> {
  static const _prefix = 'alarm.';

  @override
  AlarmPreferences build() {
    Future.microtask(_load);
    return const AlarmPreferences();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const defaults = AlarmPreferences();
      state = AlarmPreferences(
        autoAlarm: prefs.getBool('${_prefix}auto') ?? defaults.autoAlarm,
        repeatOnce: prefs.getBool('${_prefix}repeat') ?? defaults.repeatOnce,
        tellGuardian:
            prefs.getBool('${_prefix}guardian') ?? defaults.tellGuardian,
        morningHour: prefs.getInt('${_prefix}morning') ?? defaults.morningHour,
        eveningHour: prefs.getInt('${_prefix}evening') ?? defaults.eveningHour,
      );
    } catch (_) {
      // 저장소를 못 열면 기본값으로 둔다.
    }
    // 저장소를 못 열었어도 기본값대로는 울려야 한다.
    await ref.read(reminderNotificationsProvider).sync(state);
  }

  Future<void> update(AlarmPreferences next) async {
    state = next;
    // 저장이 실패해도 전화기 알림은 지금 고른 값을 따라가야 한다.
    unawaited(ref.read(reminderNotificationsProvider).sync(next));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${_prefix}auto', next.autoAlarm);
      await prefs.setBool('${_prefix}repeat', next.repeatOnce);
      await prefs.setBool('${_prefix}guardian', next.tellGuardian);
      await prefs.setInt('${_prefix}morning', next.morningHour);
      await prefs.setInt('${_prefix}evening', next.eveningHour);
    } catch (_) {
      // 화면에는 이미 반영됐다. 다음 실행 때 기본값으로 돌아갈 뿐이다.
    }
  }
}

final alarmPreferencesProvider =
    NotifierProvider<AlarmPreferencesController, AlarmPreferences>(
      AlarmPreferencesController.new,
    );
