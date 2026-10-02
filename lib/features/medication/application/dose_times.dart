import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/medication_models.dart';

/// 홈 화면에 적는 "약 드시는 시간" — 아침·점심·저녁이 몇 시인지.
///
/// **복약 알림과는 따로 간다.** 이쪽은 화면에 적어 두는 시각이고,
/// 소리로 울리는 시각은 복약 알림에서 따로 고른다. 집집마다 아침이
/// 몇 시인지가 달라서 기본값(08:00·12:00·18:00)을 고칠 수 있게 둔다.
///
/// 시각은 자정부터 몇 분인지로 센다(0~1439). 9시 30분처럼 분까지
/// 고를 수 있어야 하기 때문이다.
@immutable
class DoseTimes {
  final int morning;
  final int lunch;
  final int dinner;

  const DoseTimes({this.morning = 480, this.lunch = 720, this.dinner = 1080});

  int of(DoseSlot slot) => switch (slot) {
    DoseSlot.morning => morning,
    DoseSlot.lunch => lunch,
    DoseSlot.dinner => dinner,
  };

  DoseTimes withTime(DoseSlot slot, int time) => DoseTimes(
    morning: slot == DoseSlot.morning ? time : morning,
    lunch: slot == DoseSlot.lunch ? time : lunch,
    dinner: slot == DoseSlot.dinner ? time : dinner,
  );

  /// "09:30" — 24시간 시계.
  String clock(DoseSlot slot) => clockOf(of(slot));

  static String clockOf(int time) {
    final hour = (time ~/ 60).toString().padLeft(2, '0');
    final minute = (time % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class DoseTimesController extends Notifier<DoseTimes> {
  static const _prefix = 'doseTime.';

  @override
  DoseTimes build() {
    Future.microtask(_load);
    return const DoseTimes();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const defaults = DoseTimes();
      state = DoseTimes(
        morning: _read(prefs, 'morning') ?? defaults.morning,
        lunch: _read(prefs, 'lunch') ?? defaults.lunch,
        dinner: _read(prefs, 'dinner') ?? defaults.dinner,
      );
    } catch (_) {
      // 저장소를 못 열면 기본 시각으로 둔다.
    }
  }

  /// 분 단위 값을 읽는다. 없으면 시만 적어 두었던 옛 값을 옮겨 온다.
  static int? _read(SharedPreferences prefs, String name) {
    final minutes = prefs.getInt('$_prefix${name}Min');
    if (minutes != null) return minutes;
    final hour = prefs.getInt('$_prefix$name');
    return hour == null ? null : hour * 60;
  }

  Future<void> update(DoseTimes next) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('${_prefix}morningMin', next.morning);
      await prefs.setInt('${_prefix}lunchMin', next.lunch);
      await prefs.setInt('${_prefix}dinnerMin', next.dinner);
    } catch (_) {
      // 화면에는 이미 반영됐다. 다음 실행 때 기본값으로 돌아갈 뿐이다.
    }
  }
}

final doseTimesProvider = NotifierProvider<DoseTimesController, DoseTimes>(
  DoseTimesController.new,
);
