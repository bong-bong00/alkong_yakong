import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// 이 클래스가 "실패를 설계한다"는 원칙이 사는 자리다 —
/// 되돌리기, 중복 복용 차단, 재알림 사다리 취소가 전부 여기를 지난다.
class MedicationController extends Notifier<TodayMedication> {
  // TODO: 백엔드 복약 스케줄 API로 교체한다.
  @override
  TodayMedication build() {
    return const TodayMedication(
      doses: [
        DoseEntry(
          slot: DoseSlot.morning,
          medicines: [
            Medicine(
              ingredient: '암로디핀 5mg',
              amount: '1알',
              appearance: '노란 길쭉한 알약',
            ),
            Medicine(
              ingredient: '아스피린 100mg',
              amount: '1알',
              appearance: '흰색 동그란 알약',
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
            ),
            Medicine(
              ingredient: '암로디핀 5mg',
              amount: '1알',
              appearance: '노란 길쭉한 알약',
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

  /// 이 시간대에 보호자 알림이 나갔는지. 되돌리면 취소된다.
  final Set<DoseSlot> _guardianNotified = <DoseSlot>{};

  /// "30분 뒤에 다시"를 누른 횟수. 사다리가 그만큼 뒤로 밀린다.
  final Map<DoseSlot, int> _snoozeCount = <DoseSlot, int>{};

  bool guardianNotifiedFor(DoseSlot slot) => _guardianNotified.contains(slot);

  /// "먹었어요"를 눌렀을 때 무엇을 해야 하는지 판정한다.
  ///
  /// - 이미 기록된 시간대 → [DoseCheckOutcome.alreadyTaken] (5f 차단 시트)
  /// - 복약 시각에서 4시간 이상 지남 → [DoseCheckOutcome.tooLate] (지연 시트)
  /// - 그 외 → 기록하고 [DoseCheckOutcome.recorded]
  ///
  /// **사후 안내가 아니라 사전 차단이다.** 판정이 기록보다 먼저다.
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

  /// 지연 복약 시트에서 "그래도 먹었어요"를 골랐을 때.
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
    // 어느 단계에서든 기록되면 이후 알림은 전부 취소된다.
    ref.read(reminderSchedulerProvider).cancelSlot(slot);
    _snoozeCount.remove(slot);
    _guardianNotified.add(slot);
  }

  /// 되돌리기 (4b).
  ///
  /// **시간 제한 없이** 되돌릴 수 있다 — 시니어는 실수를 늦게 발견한다.
  /// 되돌리면 보호자에게 나간 알림도 함께 취소된다.
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

  /// "30분 뒤에 다시 알려주기".
  /// 사다리 전체가 30분 뒤로 밀린다 — 단계를 건너뛰지 않는다.
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
