import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../network/api_config.dart';

/// Read-only Flutter presentation fixtures. Never sent to a registration API.
abstract final class PresentationHistory {
  static const userId = '188d5c77-56b9-442d-9275-9a5f7f28a759';
  static const marker = 'DEMO_SYNTHETIC_20261006';
  static const medicineCode = 'DEMO-PRESENTATION-20261006';
  static const prescriptionId = 'DEMO-20261006-$userId';
  static const medicineName = '시연용 가상약(실제 약 아님)';
  static const enabled = bool.fromEnvironment(
    'PRESENTATION_HISTORY',
    defaultValue: true,
  );

  static bool applies(String id) =>
      kDebugMode && enabled && id.trim() == userId;
  static bool includesDay(String id, DateTime date) =>
      applies(id) &&
      date.year == 2026 &&
      date.month == 9 &&
      date.day >= 21 &&
      date.day <= 27;

  static List<Map<String, dynamic>> get schedules => [
    for (var day = 21; day <= 27; day++)
      for (final slot in [('아침', '08:00'), ('점심', '12:00'), ('저녁', '20:00')])
        {
          'date': '2026-09-$day',
          'slot': slot.$1,
          'time': slot.$2,
          'taken':
              !(day == 23 && slot.$1 == '점심' || day == 26 && slot.$1 == '저녁'),
          'taken_at':
              day == 23 && slot.$1 == '점심' || day == 26 && slot.$1 == '저녁'
              ? null
              : '2026-09-${day}T${slot.$2}:00+09:00',
          'medicine_code': medicineCode,
          'marker': marker,
        },
  ];

  static DateTime? takenAt(String id, DateTime day, String slot, bool taken) {
    if (!includesDay(id, day) || !taken) return null;
    final hour = switch (slot) {
      '아침' => 8,
      '점심' => 12,
      '저녁' => 20,
      _ => -1,
    };
    return hour < 0 ? null : DateTime(day.year, day.month, day.day, hour);
  }

  static List<dynamic> mergeHistory(String id, List<dynamic> real) {
    if (!applies(id)) return real;
    final days = {
      for (final row in real)
        if (row is Map) row['date'].toString(): row,
    };
    for (var day = 21; day <= 27; day++) {
      final date = '2026-09-$day';
      // Existing server dates always win. Do not disguise real missed doses.
      days.putIfAbsent(
        date,
        () => {
          'date': date,
          'total': 3,
          'taken': day == 23 || day == 26 ? 2 : 3,
          'missed_slots': [if (day == 23) '점심', if (day == 26) '저녁'],
          'marker': marker,
        },
      );
    }
    return days.values.toList();
  }

  static Map<String, dynamic> mergeCalendar(
    String id,
    int year,
    int month,
    Map real,
  ) {
    if (!applies(id) || year != 2026 || month != 9) {
      return Map<String, dynamic>.from(real);
    }
    final days = <int, Map>{
      if (real['days'] is List)
        for (final row in real['days'])
          if (row is Map) (row['day'] as num).toInt(): row,
    };
    for (var day = 1; day <= 30; day++) {
      final existing = days[day];
      if (day >= 21 &&
          day <= 27 &&
          (existing == null ||
              existing['slots'] is! List ||
              (existing['slots'] as List).isEmpty)) {
        days[day] = {
          'day': day,
          'mark': day == 23 || day == 26 ? 'missed' : 'done',
          'slots': [
            for (final row in schedules)
              if (row['date'] == '2026-09-$day') row,
          ],
          'marker': marker,
        };
      } else {
        days.putIfAbsent(
          day,
          () => {'day': day, 'mark': 'noRecord', 'slots': []},
        );
      }
    }
    return {
      ...real,
      'year': year,
      'month': month,
      'leading_blanks': DateTime(year, month).weekday - 1,
      'has_schedules': true,
      'days': [for (var day = 1; day <= 30; day++) days[day]],
      'missed': [
        if (real['missed'] is List) ...real['missed'],
        for (final day in [23, 26])
          if (days[day]?['marker'] == marker &&
              !(real['missed'] is List &&
                  (real['missed'] as List).any(
                    (row) => row is Map && row['label'] == '9월 $day일',
                  )))
            {
              'label': '9월 $day일',
              'detail': '${day == 23 ? '점심' : '저녁'} 미복용 · 시연용',
            },
      ],
    };
  }

  static Future<Map<String, dynamic>> fetchCalendar(
    String id,
    int year,
    int month, {
    ApiClient? api,
  }) async {
    Map real = {};
    try {
      final response =
          await (api ?? ApiClient(baseUrl: ApiConfig.localFeatureBaseUrl)).get(
            '/api/v1/users/${Uri.encodeComponent(id)}/medication-calendar?year=$year&month=$month',
          );
      if (response is Map) real = response;
    } catch (_) {
      if (!applies(id) || year != 2026 || month != 9) rethrow;
      debugPrint('[PRESENTATION_HISTORY] 서버 달력 조회 실패: 시연 기록만 표시');
    }
    return mergeCalendar(id, year, month, real);
  }

  static Map<String, dynamic> get prescription => {
    'id': prescriptionId,
    'prescribed_date': '2026-09-21',
    'hospital_name': '시연용 가상 처방전',
    'marker': marker,
    'status': 'EXPIRED',
    'items': [
      {
        'medicine_code': medicineCode,
        'product_name': medicineName,
        'duration_days': 7,
      },
    ],
  };
}
