import 'package:flutter_test/flutter_test.dart';
import 'package:polarbetty/biosignal/domain/hrv_calculator.dart';

void main() {
  group('HrvCalculator Tests', () {
    final calculator = HrvCalculator();

    test('filterPpi should filter out values outside 300~1500ms', () {
      final rawData = [200, 300, 800, 1500, 1600];
      final filtered = calculator.filterPpi(rawData);
      expect(filtered, [300, 800, 1500]);
    });

    test('calculateRmssd should correctly calculate RMSSD', () {
      // RMSSD = sqrt( (diff1^2 + diff2^2 + ...) / N-1 )
      // Let's use simple data: [1000, 1020, 1010]
      // diffs: (1020-1000)=20, (1010-1020)=-10
      // squares: 400, 100 -> sum = 500
      // mean = 500 / 2 = 250
      // RMSSD = sqrt(250) ≈ 15.811
      final ppiList = [1000, 1020, 1010];
      final rmssd = calculator.calculateRmssd(ppiList);
      expect(rmssd, closeTo(15.811, 0.001));
    });

    test('calculateRmssd should return 0.0 if list has less than 2 items', () {
      expect(calculator.calculateRmssd([1000]), 0.0);
      expect(calculator.calculateRmssd([]), 0.0);
    });
  });
}
