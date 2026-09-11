import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/session/mvp_session.dart';
import '../../medicines/domain/display_policy.dart';
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
/// 서버 응답을 우선한다. 서버가 빈 목록을 주면 데모약을 치운다.
/// (빈 응답인데 데모를 남기면 가짜 약이 실약처럼 보임)
/// 네트워크 실패 시에만 기존(또는 데모) 상태를 유지한다.
class MedicationController extends Notifier<TodayMedication> {
  final _api = ApiClient();

  @override
  TodayMedication build() {
    Future.microtask(refreshFromServer);
    return const TodayMedication(
      doses: [],
      guardianRelation: '보호자',
      guardianName: '가족',
      heartRate: 72,
      heartRateNormal: true,
    );
  }

  Future<void> refreshFromServer() async {
    try {
      final userId = Uri.encodeComponent(MvpSession.userId);
      final response = await _api.get('/api/v1/users/$userId/today-medicines');
      if (response is! Map) return;
      final parsed = _fromServer(Map<String, dynamic>.from(response));
      // 서버가 정상 응답했으면 비어 있어도 그대로 반영 (데모 유지 금지)
      state = parsed;
    } catch (_) {
      // 서버 불가면 현재 상태(최초엔 데모) 유지
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
            final card = resolveMyMedicineCard(
              medicineCode: m['medicine_code']?.toString(),
              productName: m['product_name']?.toString(),
              displayName: m['display_name']?.toString(),
              ingredient: m['ingredient']?.toString(),
              purposeLabel: m['purpose_label']?.toString(),
              shortExplanation: m['short_explanation']?.toString(),
              easyCategory: m['easy_category']?.toString(),
            );
            if (isMockDrugInfoName(card.name)) continue;
            final scheduleRaw = m['schedule_id'];
            final scheduleId = scheduleRaw is num
                ? scheduleRaw.toInt()
                : int.tryParse(scheduleRaw?.toString() ?? '');
            meds.add(
              Medicine(
                ingredient: card.name,
                ingredientName:
                    m['ingredient_name']?.toString() ??
                    m['ingredient']?.toString(),
                ingredientSummary: m['ingredient_summary']?.toString(),
                ingredientStrength: m['ingredient_strength']?.toString(),
                amount: m['amount']?.toString() ?? '',
                easyCategory: card.spoken,
                purposeLabel: card.purposeLabel,
                shortExplanation: card.spoken,
                keyCaution: m['key_caution']?.toString(),
                efficacy: null,
                scheduleId: scheduleId,
                medicineCode: m['medicine_code']?.toString(),
              ),
            );
          }
        }
        if (meds.isEmpty) continue;
        doses.add(
          DoseEntry(slot: slot, medicines: meds, taken: raw['taken'] == true),
        );
      }
    }
    return TodayMedication(
      doses: doses,
      guardianRelation: data['guardian_relation']?.toString() ?? '보호자',
      guardianName: data['guardian_name']?.toString() ?? '가족',
      heartRate: 72,
      heartRateNormal: true,
      daysLeft: state.daysLeft,
      interactionAlert: data['interaction_alert']?.toString(),
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

  final Set<DoseSlot> _guardianNotified = <DoseSlot>{};
  final Map<DoseSlot, int> _snoozeCount = <DoseSlot, int>{};
  bool _refillAsked = false;

  bool get shouldAskRefill => state.daysLeft == 0 && !_refillAsked;

  void markRefillAsked() => _refillAsked = true;

  void refill({int days = 21}) {
    _refillAsked = false;
    state = state.copyWith(daysLeft: days);
  }

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
    _postTakenLogs(slot);
  }

  Future<void> _postTakenLogs(DoseSlot slot) async {
    final dose = state.doseOf(slot);
    final userId = MvpSession.userId.trim();
    if (userId.isEmpty) return;
    for (final med in dose.medicines) {
      final scheduleId = med.scheduleId;
      if (scheduleId == null || scheduleId <= 0) continue;
      try {
        await _api.post(
          '/api/v1/medication-logs',
          body: {'user_id': userId, 'schedule_id': scheduleId},
        );
      } catch (_) {
        // 로컬 기록은 유지. 서버 실패는 다음에 동기화 가능.
      }
    }
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

  void decrementDaysLeft() {
    final next = state.daysLeft <= 0 ? 0 : state.daysLeft - 1;
    state = state.copyWith(daysLeft: next);
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
