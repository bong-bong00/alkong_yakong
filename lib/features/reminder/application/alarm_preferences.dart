import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reminder_notifications.dart';

/// 복약 알림 설정. 앱을 껐다 켜도 고른 값이 남는다.
///
/// 시각은 **자정부터 몇 분인지**로 센다(0~1439). 9시 30분처럼 분까지
/// 고를 수 있어야 하기 때문이다. 화면에는 24시간 시계로 "09:30"이라 적는다.
@immutable
class AlarmPreferences {
  final bool autoAlarm;
  final bool repeatOnce;
  final bool tellGuardian;

  /// 들어온 그대로의 시각 목록. 읽을 때는 [times]로 정리해서 쓴다.
  ///
  /// 처음 값은 홈의 "약 드시는 시간" 기본값(08:00·12:00·18:00)과 같다.
  /// 그 뒤로는 복약 알림에서 따로 고친다.
  final List<int> _rawTimes;

  /// 목록에는 남기되 이번엔 울리지 않을 시각.
  ///
  /// 지우는 것과 다르다 — 지우면 다시 넣을 때 시각을 또 골라야 한다.
  /// 잠깐 안 받고 싶은 때를 스위치 하나로 껐다 켜게 둔다.
  final List<int> _rawMuted;

  const AlarmPreferences({
    this.autoAlarm = true,
    this.repeatOnce = true,
    this.tellGuardian = true,
    List<int> times = const [480, 720, 1080],
    List<int> mutedTimes = const [],
  }) : _rawTimes = times,
       _rawMuted = mutedTimes;

  /// 알림 시각(자정부터 분). 오름차순이고 겹치지 않는다. 적어도 하나는 남는다.
  List<int> get times => normalize(_rawTimes);

  /// 꺼 둔 시각. 목록에 남아 있는 것만 센다.
  Set<int> get mutedTimes => {
    for (final time in _rawMuted)
      if (times.contains(time)) time,
  };

  /// 실제로 울릴 시각.
  List<int> get ringingTimes => [
    for (final time in times)
      if (!mutedTimes.contains(time)) time,
  ];

  bool isMuted(int time) => mutedTimes.contains(time);

  /// 한 시각만 껐다 켠다.
  AlarmPreferences withMuted(int time, bool muted) => copyWith(
    mutedTimes: [
      for (final t in mutedTimes)
        if (t != time) t,
      if (muted) time,
    ],
  );

  /// 한 사람이 챙길 수 있는 알림은 이 정도가 끝이다.
  static const int maxTimes = 6;

  AlarmPreferences copyWith({
    bool? autoAlarm,
    bool? repeatOnce,
    bool? tellGuardian,
    List<int>? times,
    List<int>? mutedTimes,
  }) => AlarmPreferences(
    autoAlarm: autoAlarm ?? this.autoAlarm,
    repeatOnce: repeatOnce ?? this.repeatOnce,
    tellGuardian: tellGuardian ?? this.tellGuardian,
    times: normalize(times ?? this.times),
    mutedTimes: mutedTimes ?? _rawMuted,
  );

  /// 시각을 더한다. 이미 있는 시각이면 그대로 둔다.
  AlarmPreferences withTime(int time) =>
      times.contains(time) || times.length >= maxTimes
      ? this
      : copyWith(times: [...times, time]);

  /// 시각을 지운다. 마지막 하나는 지우지 않는다 — 알림이 통째로 사라진다.
  AlarmPreferences withoutTime(int time) => times.length <= 1
      ? this
      : copyWith(
          times: [
            for (final t in times)
              if (t != time) t,
          ],
        );

  /// [was]를 [now]로 바꾼다. 꺼 둔 표시도 새 시각으로 따라간다.
  AlarmPreferences replaceTime(int was, int now) => copyWith(
    times: [
      for (final t in times)
        if (t == was) now else t,
    ],
    mutedTimes: [
      for (final t in _rawMuted)
        if (t == was) now else t,
    ],
  );

  /// 겹치는 시각을 덜어내고 순서대로 세운다. 비면 기본값으로 돌린다.
  static List<int> normalize(List<int> raw) {
    final kept = <int>{
      for (final time in raw)
        if (time >= 0 && time < 24 * 60) time,
    }.toList()..sort();
    if (kept.isEmpty) return const [480];
    return List<int>.unmodifiable(kept.take(maxTimes));
  }

  /// "09:30" — 24시간 시계.
  static String clock(int time) {
    final hour = (time ~/ 60).toString().padLeft(2, '0');
    final minute = (time % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// 내 정보 목록에 쓰는 한 줄.
  String get summary => !autoAlarm || ringingTimes.isEmpty
      ? '소리 알림이 꺼져 있어요'
      : '${ringingTimes.map(clock).join(' · ')} · 소리로 알려드려요';
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
        times: _readTimes(prefs) ?? defaults.times,
        mutedTimes: _readMuted(prefs),
      );
    } catch (_) {
      // 저장소를 못 열면 기본값으로 둔다.
    }
    // 저장소를 못 열었어도 기본값대로는 울려야 한다.
    await ref.read(reminderNotificationsProvider).sync(state);
  }

  /// 분 단위 목록을 읽는다. 없으면 시 단위로 적어 두었던 옛 값을 옮겨 온다.
  static List<int>? _readTimes(SharedPreferences prefs) {
    final stored = prefs.getStringList('${_prefix}times');
    if (stored != null && stored.isNotEmpty) {
      return AlarmPreferences.normalize([
        for (final text in stored) int.tryParse(text) ?? -1,
      ]);
    }
    final hours = prefs.getStringList('${_prefix}hours');
    if (hours != null && hours.isNotEmpty) {
      return AlarmPreferences.normalize([
        for (final text in hours) (int.tryParse(text) ?? -1) * 60,
      ]);
    }
    final morning = prefs.getInt('${_prefix}morning');
    final evening = prefs.getInt('${_prefix}evening');
    if (morning == null && evening == null) return null;
    return AlarmPreferences.normalize([
      if (morning != null) morning * 60,
      if (evening != null) evening * 60,
    ]);
  }

  static List<int> _readMuted(SharedPreferences prefs) {
    final stored = prefs.getStringList('${_prefix}mutedTimes');
    if (stored != null) {
      return [for (final text in stored) int.tryParse(text) ?? -1];
    }
    return [
      for (final text in prefs.getStringList('${_prefix}muted') ?? const [])
        (int.tryParse(text) ?? -1) * 60,
    ];
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
      await prefs.setStringList('${_prefix}times', [
        for (final time in next.times) '$time',
      ]);
      await prefs.setStringList('${_prefix}mutedTimes', [
        for (final time in next.mutedTimes) '$time',
      ]);
    } catch (_) {
      // 화면에는 이미 반영됐다. 다음 실행 때 기본값으로 돌아갈 뿐이다.
    }
  }
}

final alarmPreferencesProvider =
    NotifierProvider<AlarmPreferencesController, AlarmPreferences>(
      AlarmPreferencesController.new,
    );
