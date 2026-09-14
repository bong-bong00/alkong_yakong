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

  /// 이 값 이상이면 빠른 것으로 본다. 서버 biosignal_service.FAST_BPM 과 같다.
  /// 화면 문구("기준 80회보다 빠릅니다")도 이 값을 읽어 판정과 어긋나지 않게 한다.
  static const int fastBpm = 80;

  static bool isFast(int bpm) => bpm >= fastBpm;
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
/// `/api/v1/users/{id}/biosignal/heart-summary` 응답을 `HeartRepository`가
/// 이 모양으로 옮긴다. 화면은 **읽어 온 값만** 그린다 — 못 읽었으면
/// 불러오는 중·못 불러옴·기록 없음을 그대로 말한다.
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

  /// 오늘·이번 주·이번 달 중 한 번이라도 잰 값이 있는지.
  ///
  /// 서버는 기록이 없어도 빈 칸 7개·날짜 칸 N개를 채워 보낸다.
  /// 칸이 있다고 기록이 있는 것은 아니므로 값으로 판단한다.
  bool get hasReadings {
    bool has(HeartPair p) => p.before != null || p.after != null;
    return has(today) ||
        week.any((d) => has(d.pair)) ||
        month.any((d) => has(d.pair));
  }

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
