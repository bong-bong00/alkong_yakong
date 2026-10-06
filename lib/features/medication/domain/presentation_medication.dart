import '../../../core/session/presentation_history.dart';
import 'medication_models.dart';

/// A local presentation state only; never written during initialization.
bool appliesPresentationMedication(String userId, DateTime now) =>
    PresentationHistory.applies(userId) &&
    now.year == 2026 &&
    now.month == 10 &&
    now.day == 6;

TodayMedication preparePresentationMedication(
  TodayMedication serverState, {
  required String userId,
  required DateTime now,
  required bool lunchTaken,
}) {
  if (!appliesPresentationMedication(userId, now)) return serverState;
  return serverState.copyWith(
    doses: [
      for (final dose in serverState.doses)
        if (dose.slot == DoseSlot.morning)
          dose.copyWith(taken: true)
        else if (dose.slot == DoseSlot.lunch)
          dose.copyWith(taken: lunchTaken, clearTakenAt: !lunchTaken)
        else
          dose,
    ],
  );
}
