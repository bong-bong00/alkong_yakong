import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/core/session/presentation_history.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_data.dart';
import 'package:alkong_yakong/features/dashboard/application/presentation_lunch.dart';

void main() {
  final day = DateTime(2026, 10, 6, 14);
  HeartReading reading({
    int id = 47,
    int bpm = 75,
    HeartMeasurementContext context = HeartMeasurementContext.beforeMedication,
    int hour = 13,
    int minute = 55,
  }) => HeartReading(
    id: id,
    bpm: bpm,
    measuredAt: DateTime(2026, 10, 6, hour, minute),
    measurementContext: context,
  );

  test('restores only stored demo lunch pre-measurement', () {
    expect(
      presentationLunchBeforeBpm(PresentationHistory.userId, day, [reading()]),
      75,
    );
  });
  test('does not prepare other accounts or dates', () {
    expect(presentationLunchBeforeBpm('other-user', day, [reading()]), isNull);
    expect(
      presentationLunchBeforeBpm(
        PresentationHistory.userId,
        DateTime(2026, 10, 7),
        [reading()],
      ),
      isNull,
    );
  });
  test('never invents missing data or uses general/after measurements', () {
    for (final records in <List<HeartReading>>[
      [],
      [reading(id: 51)],
      [reading(bpm: 78)],
      [reading(hour: 8, minute: 5)],
      [reading(context: HeartMeasurementContext.general)],
      [reading(context: HeartMeasurementContext.afterMedication)],
    ]) {
      expect(
        presentationLunchBeforeBpm(PresentationHistory.userId, day, records),
        isNull,
      );
    }
  });
}
