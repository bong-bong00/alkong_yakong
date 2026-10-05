import '../../../core/session/presentation_history.dart';
import '../../biosignal/domain/heart_data.dart';

/// Restores only the agreed demo lunch preparation, from a stored reading.
/// It never invents a measurement or marks a dose as taken.
int? presentationLunchBeforeBpm(
  String userId,
  DateTime now,
  List<HeartReading> readings,
) {
  if (!PresentationHistory.applies(userId) ||
      now.year != 2026 ||
      now.month != 10 ||
      now.day != 6) {
    return null;
  }
  for (final reading in readings) {
    final at = reading.measuredAt.toLocal();
    if (reading.id == 47 &&
        reading.measurementContext ==
            HeartMeasurementContext.beforeMedication &&
        reading.bpm == 75 &&
        at.year == 2026 &&
        at.month == 10 &&
        at.day == 6 &&
        at.hour == 13 &&
        at.minute == 55) {
      return reading.bpm;
    }
  }
  return null;
}
