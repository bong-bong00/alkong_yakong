import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/features/medicines/domain/official_usage_display.dart';

void main() {
  test('redundant leading tablet title is removed without changing dosing', () {
    const dosing = '성인 : 메퀴타진으로서 1회 5mg 1일 2회 경구 투여한다.';
    expect(orderOfficialUsageSections('(정제)\n\n$dosing'), dosing);
    expect(
      orderOfficialUsageSections('제형별 안내\n(정제)\n$dosing'),
      '제형별 안내\n(정제)\n$dosing',
    );
  });
  test('age groups are reordered with all conditions preserved', () {
    const text = '성인 : 초기 600mg. 유지량 200mg.\n소아 : 별도 용량.\n고령자 : 감량 조건.';
    expect(
      orderOfficialUsageSections(text),
      '고령자 : 감량 조건.\n\n성인 : 초기 600mg. 유지량 200mg.\n\n소아 : 별도 용량.',
    );
  });
  test('unlabelled official instructions are not guessed or shortened', () {
    const text = '하루 한 번 바른다. 증상에 따라 조절한다.';
    expect(orderOfficialUsageSections(text), text);
    expect(orderOfficialUsageSections(' '), '');
  });
}
