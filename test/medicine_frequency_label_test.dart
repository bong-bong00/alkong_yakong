import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('약 목록은 복용량 대신 실제 하루 횟수를 표시한다', () {
    const tablet = Medicine(
      ingredient: '테스트정',
      amount: '0.5알',
      frequencyPerDay: 3,
    );
    const liquid = Medicine(
      ingredient: '테스트액',
      amount: '1회',
      frequencyPerDay: 1,
    );
    expect(tablet.frequencyLabel, '하루 3회');
    expect(liquid.frequencyLabel, '하루 1회');
    expect(tablet.amount, '0.5알');
    for (final frequency in <int?>[null, 0, -1]) {
      final medicine = Medicine(
        ingredient: '횟수 미확인 약',
        amount: '1알',
        frequencyPerDay: frequency,
      );
      expect(medicine.frequencyLabel, '횟수 확인 필요');
    }
  });
}
