import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/prescription_history_screen.dart';

void main() {
  test('처방전 기록은 서버가 다듬은 이름을 먼저 쓴다', () {
    final record = PrescriptionRecord.fromJson({
      'prescribed_date': '2023-10-30',
      'items': [
        {
          'display_name': '휴온스시메티딘정200밀리그램',
          'product_name': '휴온스시메티딘정200밀리그램(수출명:TAGAMENTTab.200밀리그램)',
          'ocr_drug_name': '시메티딘정',
        },
        // 예전 서버는 display_name을 주지 않는다.
        {'product_name': '프리마란정(메퀴타진)', 'ocr_drug_name': '프리마란정'},
      ],
    });

    expect(record.medicines.map((line) => line.name), [
      '휴온스시메티딘정200밀리그램',
      '프리마란정(메퀴타진)',
    ]);
  });
}
