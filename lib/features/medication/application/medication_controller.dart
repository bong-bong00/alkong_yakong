import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/session/mvp_session.dart';
import '../../reminder/domain/reminder_ladder.dart';
import '../domain/medication_models.dart';

/// 복약 시각에서 이만큼 지나면 지연 복약으로 본다.
const Duration kLateDoseThreshold = Duration(hours: 4);

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => InMemoryReminderScheduler(),
);

final medicationProvider =
    NotifierProvider<MedicationController, TodayMedication>(
      MedicationController.new,
    );

/// 오늘 복약 상태를 들고 있는 컨트롤러.
///
/// 서버 `user_medicines` 를 우선 읽고, 실패/비어 있으면 로컬 데모를 유지한다.
class MedicationController extends Notifier<TodayMedication> {
  final _api = ApiClient();

  @override
  TodayMedication build() {
    Future.microtask(refreshFromServer);
    return _demoToday();
  }

  Future<void> refreshFromServer() async {
    try {
      final userId = Uri.encodeComponent(MvpSession.userId);
      final response = await _api.get('/api/v1/users/$userId/today-medicines');
      if (response is! Map) return;
      final parsed = _fromServer(Map<String, dynamic>.from(response));
      if (parsed.doses.isEmpty) return;
      state = parsed;
    } catch (_) {
      // 서버 불가면 데모 유지
    }
  }

  TodayMedication _fromServer(Map<String, dynamic> data) {
    final rawDoses = data['doses'];
    final doses = <DoseEntry>[];
    if (rawDoses is List) {
      for (final raw in rawDoses) {
        if (raw is! Map) continue;
        final slot = _slotOf(raw['slot']?.toString());
        if (slot == null) continue;
        final meds = <Medicine>[];
        final rawMeds = raw['medicines'];
        if (rawMeds is List) {
          for (final m in rawMeds) {
            if (m is! Map) continue;
            final ingredient =
                m['ingredient']?.toString() ??
                m['product_name']?.toString() ??
                '약';
            meds.add(
              Medicine(
                ingredient: ingredient,
                amount: m['amount']?.toString() ?? '1알',
                easyCategory: m['easy_category']?.toString(),
              ),
            );
          }
        }
        if (meds.isEmpty) continue;
        doses.add(
          DoseEntry(
            slot: slot,
            medicines: meds,
            taken: raw['taken'] == true,
          ),
        );
      }
    }
    return TodayMedication(
      doses: doses,
      guardianRelation: data['guardian_relation']?.toString() ?? '보호자',
      guardianName: data['guardian_name']?.toString() ?? '가족',
      heartRate: 72,
      heartRateNormal: true,
    );
  }

  DoseSlot? _slotOf(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'morning':
        return DoseSlot.morning;
      case 'lunch':
        return DoseSlot.lunch;
      case 'dinner':
        return DoseSlot.dinner;
      default:
        return null;
    }
  }

  TodayMedication _demoToday() {
    return const TodayMedication(
      doses: [
        DoseEntry(
          slot: DoseSlot.morning,
          medicines: [
            Medicine(
              ingredient: '암로디핀 5mg',
              amount: '1알',
              appearance: '노란 길쭉한 알약',
              easyCategory: '혈압 낮춤',
            ),
            Medicine(
              ingredient: '아스피린 100mg',
              amount: '1알',
              appearance: '흰색 동그란 알약',
              easyCategory: '피 묽게',
            ),
          ],
          taken: true,
        ),
        DoseEntry(
          slot: DoseSlot.lunch,
          medicines: [
            Medicine(
              ingredient: '메트포르민 500mg',
              amount: '1알',
              appearance: '흰색 동그란 알약',
              easyCategory: '혈당 조절',
            ),
          ],
          taken: true,
        ),
        DoseEntry(
          slot: DoseSlot.dinner,
          medicines: [
            Medicine(
              ingredient: '메트포르민 500mg',
              amount: '1알',
              appearance: '흰색 동그란 알약',
              easyCategory: '혈당 조절',
            ),
            Medicine(
              ingredient: '암로디핀 5mg',
              amount: '1알',
              appearance: '노란 길쭉한 알약',
              easyCategory: '혈압 낮춤',
            ),
          ],
        ),
      ],
      guardianRelation: '딸',
      guardianName: '지안',
      heartRate: 72,
      heartRateNormal: true,
    );
  }

  final Set<DoseSlot> _guardianNotified = <DoseSlot>{};
  final Map<DoseSlot, int> _snoozeCount = <DoseSlot, int>{};

  bool guardianNotifiedFor(DoseSlot slot) => _guardianNotified.contains(slot);

  DoseCheckOutcome take(DoseSlot slot, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final dose = state.doseOf(slot);

    if (dose.taken) return DoseCheckOutcome.alreadyTaken;

    final scheduled = slot.todayAt(at);
    if (at.difference(scheduled) > kLateDoseThreshold) {
      return DoseCheckOutcome.tooLate;
    }

    _record(slot, at);
    return DoseCheckOutcome.recorded;
  }

  void takeAnyway(DoseSlot slot, {DateTime? now}) {
    _record(slot, now ?? DateTime.now());
  }

  void _record(DoseSlot slot, DateTime at) {
    state = state.copyWith(
      doses: [
        for (final dose in state.doses)
          if (dose.slot == slot)
            dose.copyWith(taken: true, takenAt: at, clearSnooze: true)
          else
            dose,
      ],
    );
    ref.read(reminderSchedulerProvider).cancelSlot(slot);
    _snoozeCount.remove(slot);
    _guardianNotified.add(slot);
  }

  void undo(DoseSlot slot) {
    state = state.copyWith(
      doses: [
        for (final dose in state.doses)
          if (dose.slot == slot)
            dose.copyWith(taken: false, clearTakenAt: true)
          else
            dose,
      ],
    );
    _guardianNotified.remove(slot);
    _scheduleLadder(slot);
  }

  DateTime snooze(DoseSlot slot, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final count = (_snoozeCount[slot] ?? 0) + 1;
    _snoozeCount[slot] = count;

    final until = slot.todayAt(at).add(ReminderLadder.snoozeInterval * count);
    state = state.copyWith(
      doses: [
        for (final dose in state.doses)
          if (dose.slot == slot) dose.copyWith(snoozedUntil: until) else dose,
      ],
    );
    _scheduleLadder(slot, now: at);
    return until;
  }

  void _scheduleLadder(DoseSlot slot, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final scheduler = ref.read(reminderSchedulerProvider);
    scheduler.cancelSlot(slot);
    scheduler.schedule(
      ReminderLadder.planFor(
        slot,
        slot.todayAt(at),
        snoozeCount: _snoozeCount[slot] ?? 0,
      ),
    );
  }
}
