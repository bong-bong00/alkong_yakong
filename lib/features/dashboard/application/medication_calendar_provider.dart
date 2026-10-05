import '../../../core/session/mvp_session.dart';
import '../../../core/session/presentation_history.dart';
import '../../../dev_mock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 한 달치 "며칠에 어느 때를 드셨는지".
///
/// 기록 탭의 한 주 칸과 전체 달력이 같은 값을 본다 — 한 주에서 날짜를
/// 누르면 그 날의 아침·점심·저녁이 아래 칸에 그대로 떠야 하기 때문이다.
///
/// 날(1~31) → {때 이름: 드셨는지}. 기록이 없는 날은 목록에 없다.
typedef MonthSlots = Map<int, Map<String, bool>>;

@immutable
class MonthKey {
  final int year;
  final int month;

  /// 보호자가 볼 어르신 id. null이면 로그인한 본인.
  final String? patientId;

  const MonthKey(this.year, this.month, [this.patientId]);

  @override
  bool operator ==(Object other) =>
      other is MonthKey &&
      other.year == year &&
      other.month == month &&
      other.patientId == patientId;

  @override
  int get hashCode => Object.hash(year, month, patientId);
}

final medicationMonthSlotsProvider =
    FutureProvider.family<MonthSlots, MonthKey>((ref, key) async {
      // 화면 확인용 가짜 달. dev_mock.dart 와 함께 지운다.
      if (mockData) {
        return {
          for (final day in mockCalendarDays(key.year, key.month))
            if (day.slots.isNotEmpty)
              day.day: {for (final slot in day.slots) slot.slot: slot.taken},
        };
      }
      final rawUserId = key.patientId?.trim().isNotEmpty == true
          ? key.patientId!.trim()
          : MvpSession.userId.trim();
      if (rawUserId.isEmpty) return const {};
      final response = await PresentationHistory.fetchCalendar(
        rawUserId,
        key.year,
        key.month,
      );
      final days = response['days'];
      if (days is! List) return const {};
      final result = <int, Map<String, bool>>{};
      for (final row in days) {
        if (row is! Map) continue;
        final day = (row['day'] as num?)?.toInt() ?? 0;
        final slots = row['slots'];
        if (day <= 0 || slots is! List) continue;
        final byName = <String, bool>{};
        for (final slot in slots) {
          if (slot is! Map) continue;
          final name = slot['slot']?.toString() ?? '';
          if (name.isEmpty) continue;
          byName[name] = slot['taken'] == true;
        }
        if (byName.isNotEmpty) result[day] = byName;
      }
      return result;
    });
