import '../../../core/network/api_client.dart';
import '../../../core/session/mvp_session.dart';
import '../domain/heart_data.dart';

/// 저장된 심박 기록을 읽어 온다.
///
/// 화면이 오늘·이번 주·한 달을 따로 부르면 그 사이 날짜가 바뀔 때
/// 서로 다른 기준의 숫자가 한 화면에 놓인다. 그래서 한 번에 받는다.
class HeartRepository {
  HeartRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// 서버에서 읽어 [HeartData]로 만든다.
  ///
  /// 못 읽으면 **null**을 돌려준다. 데모 데이터로 조용히 갈아끼우지 않는다 —
  /// 가짜 숫자를 진짜처럼 보여주면 그것대로 판단의 근거가 된다.
  Future<HeartData?> fetch({String? userId}) async {
    final id = (userId ?? MvpSession.userId).trim();
    if (id.isEmpty) return null;
    try {
      final response = await _apiClient.get(
        '/api/v1/users/${Uri.encodeComponent(id)}/biosignal/heart-summary',
      );
      if (response is! Map) return null;
      return _parse(Map<String, dynamic>.from(response));
    } catch (_) {
      return null;
    }
  }

  HeartData _parse(Map<String, dynamic> json) {
    final today = _pair(json['today']);
    final anomaly = _anomaly(json['anomaly'], today);

    return HeartData(
      today: today,
      todaySlotLabel: json['today_slot_label']?.toString() ?? '저녁 약',
      // 못 잰 쪽은 시각도 비운다. "--:--"를 채워 넣지 않는다.
      beforeAt: json['before_at']?.toString() ?? '',
      afterAt: json['after_at']?.toString() ?? '',
      week: _week(json['week']),
      month: _month(json['month']),
      streakDays: _int(json['streak_days']) ?? 0,
      bestStreakDays: _int(json['best_streak_days']) ?? 0,
      anomaly: anomaly,
      // 센서 상태는 기록이 아니라 지금 붙어 있는지의 문제라
      // 여기서 말하지 않는다. HeartSensor 쪽이 채운다.
      sensorConnected: false,
      sensorBattery: null,
      sensorLastReadAt: json['after_at']?.toString() ?? '',
      notifyGuardian: true,
    );
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  static HeartPair _pair(Object? raw) {
    if (raw is! Map) return const HeartPair();
    return HeartPair(before: _int(raw['before']), after: _int(raw['after']));
  }

  static List<HeartDay> _week(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          HeartDay(entry['weekday']?.toString() ?? '', _pair(entry)),
    ];
  }

  static List<HeartMonthDay> _month(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map && _int(entry['day']) != null)
          HeartMonthDay(_int(entry['day'])!, _pair(entry)),
    ];
  }

  static HeartAnomaly? _anomaly(Object? raw, HeartPair today) {
    if (raw is! Map) return null;
    final day = _int(raw['day']);
    final before = _int(raw['before']);
    final after = _int(raw['after']);
    // 셋 중 하나라도 없으면 "이상했던 날"이라고 말하지 않는다.
    if (day == null || before == null || after == null) return null;
    return HeartAnomaly(
      day: day,
      slotLabel: raw['label']?.toString() ?? '$day일',
      before: before,
      after: after,
    );
  }
}
