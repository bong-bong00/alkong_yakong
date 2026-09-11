import 'package:flutter/foundation.dart';

/// 복약 **전·후 한 쌍**의 심박수.
///
/// 이 앱은 심박수를 연속으로 재지 않는다. 폴라 가슴 띠로 약 먹기 전에 한 번,
/// 먹은 뒤에 한 번, **하루 두 번만** 잰다. 그래서 값은 늘 쌍으로 다닌다.
@immutable
class HeartPair {
  /// 약 먹기 전 수치. 재지 못했으면 null.
  final int? before;

  /// 약 먹은 뒤 수치. 아직 안 쟀으면 null.
  final int? after;

  const HeartPair({this.before, this.after});

  bool get isComplete => before != null && after != null;

  /// 먹은 뒤 몇 회 낮아졌는지. 올라갔으면 음수.
  int? get drop =>
      isComplete ? before! - after! : null;

  /// 80회 이상이면 빠른 것으로 본다.
  static bool isFast(int bpm) => bpm >= 80;
}

/// 이번 주 한 칸 — 요일 하나의 전·후 쌍.
@immutable
class HeartDay {
  /// "월", "화" …
  final String weekday;
  final HeartPair pair;

  const HeartDay(this.weekday, this.pair);
}

/// 한 달 기록의 하루.
@immutable
class HeartMonthDay {
  final int day;
  final HeartPair pair;

  const HeartMonthDay(this.day, this.pair);

  /// 재지 못한 날.
  bool get isMissing => pair.after == null;
}

/// 심박수 화면 전체가 쓰는 데이터 묶음.
///
/// TODO: `/api/v1/users/{id}/biosignal/...` 응답으로 채운다.
/// 지금은 핸드오프의 데모 데이터를 그대로 둔다.
@immutable
class HeartData {
  /// 오늘 잰 것.
  final HeartPair today;

  /// 오늘 어느 때 약인지. "저녁 약".
  final String todaySlotLabel;

  /// 전·후를 잰 시각.
  final String beforeAt;
  final String afterAt;

  /// 이번 주 7일.
  final List<HeartDay> week;

  /// 이번 달 날짜별.
  final List<HeartMonthDay> month;

  /// 심박수가 계속 정상인 연속 일수와 최고 기록.
  final int streakDays;
  final int bestStreakDays;

  /// 이상이 있었던 날 (없으면 null).
  final HeartAnomaly? anomaly;

  /// 센서 상태.
  final bool sensorConnected;

  /// 남은 배터리 (0~100). 기기가 아직 안 알려줬으면 null.
  /// **0으로 두지 않는다** — 0%는 "다 닳았다"는 뜻이라 모른다는 것과 다르다.
  final int? sensorBattery;
  final String sensorLastReadAt;

  /// 심박수가 빠르면 보호자에게 자동으로 알릴지.
  final bool notifyGuardian;

  const HeartData({
    required this.today,
    required this.todaySlotLabel,
    required this.beforeAt,
    required this.afterAt,
    required this.week,
    required this.month,
    required this.streakDays,
    required this.bestStreakDays,
    required this.anomaly,
    required this.sensorConnected,
    required this.sensorBattery,
    required this.sensorLastReadAt,
    required this.notifyGuardian,
  });

  /// 이번 주 모든 날이 약을 드신 뒤 낮아졌는지.
  bool get allDropped =>
      week.every((d) => (d.pair.drop ?? 0) > 0);

  HeartData copyWith({
    bool? sensorConnected,
    bool? notifyGuardian,
    HeartPair? today,
    int? sensorBattery,
  }) => HeartData(
    today: today ?? this.today,
    todaySlotLabel: todaySlotLabel,
    beforeAt: beforeAt,
    afterAt: afterAt,
    week: week,
    month: month,
    streakDays: streakDays,
    bestStreakDays: bestStreakDays,
    anomaly: anomaly,
    sensorConnected: sensorConnected ?? this.sensorConnected,
    sensorBattery: sensorBattery ?? this.sensorBattery,
    sensorLastReadAt: sensorLastReadAt,
    notifyGuardian: notifyGuardian ?? this.notifyGuardian,
  );

  /// 핸드오프 05-CONTENT-RULES §4의 데모 데이터.
  static const HeartData demo = HeartData(
    today: HeartPair(before: 78, after: 72),
    todaySlotLabel: '저녁 약',
    beforeAt: '오후 5시 52분',
    afterAt: '오후 6시 40분',
    week: [
      HeartDay('월', HeartPair(before: 80, after: 74)),
      HeartDay('화', HeartPair(before: 78, after: 71)),
      HeartDay('수', HeartPair(before: 82, after: 76)),
      HeartDay('목', HeartPair(before: 77, after: 70)),
      HeartDay('금', HeartPair(before: 84, after: 79)),
      HeartDay('토', HeartPair(before: 76, after: 70)),
      HeartDay('일', HeartPair(before: 78, after: 72)),
    ],
    month: [
      HeartMonthDay(1, HeartPair(before: 79, after: 73)),
      HeartMonthDay(2, HeartPair(before: 77, after: 71)),
      HeartMonthDay(3, HeartPair(before: 81, after: 75)),
      HeartMonthDay(4, HeartPair(before: 78, after: 72)),
      HeartMonthDay(5, HeartPair(before: 76, after: 70)),
      HeartMonthDay(6, HeartPair(before: 80, after: 74)),
      HeartMonthDay(7, HeartPair(before: 79, after: 73)),
      HeartMonthDay(8, HeartPair(before: 77, after: 72)),
      HeartMonthDay(9, HeartPair()),
      HeartMonthDay(10, HeartPair(before: 78, after: 71)),
      HeartMonthDay(11, HeartPair(before: 82, after: 76)),
      HeartMonthDay(12, HeartPair(before: 96, after: 84)),
      HeartMonthDay(13, HeartPair(before: 80, after: 74)),
      HeartMonthDay(14, HeartPair(before: 77, after: 70)),
      HeartMonthDay(15, HeartPair(before: 79, after: 73)),
      HeartMonthDay(16, HeartPair(before: 78, after: 72)),
      HeartMonthDay(17, HeartPair(before: 81, after: 75)),
      HeartMonthDay(18, HeartPair(before: 76, after: 71)),
      HeartMonthDay(19, HeartPair(before: 80, after: 74)),
      HeartMonthDay(20, HeartPair(before: 78, after: 73)),
      HeartMonthDay(21, HeartPair(before: 78, after: 72)),
    ],
    streakDays: 9,
    bestStreakDays: 14,
    anomaly: HeartAnomaly(
      day: 12,
      slotLabel: '저녁',
      before: 96,
      after: 84,
    ),
    sensorConnected: true,
    sensorBattery: 82,
    sensorLastReadAt: '오후 6시 40분',
    notifyGuardian: true,
  );
}

/// 한 달 안에서 한 번 빠르게 뛴 날.
@immutable
class HeartAnomaly {
  final int day;
  final String slotLabel;
  final int before;
  final int after;

  const HeartAnomaly({
    required this.day,
    required this.slotLabel,
    required this.before,
    required this.after,
  });
}
