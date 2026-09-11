import 'package:alkong_yakong/features/medicines/domain/display_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('허가 제품명을 제목으로 쓰고 키워드 괄호는 뗀다', () {
    final card = resolveMyMedicineCard(
      medicineCode: '197800210',
      productName: '아디팜정(히드록시진염산염)',
      displayName: '히드록시진염산염 (알레르기·두통·어지러움)',
      ingredient: '히드록시진염산염',
      purposeLabel: '가려움 완화 · 불안·긴장 완화',
      shortExplanation: '가려움 또는 불안·긴장을 완화할 목적으로 처방될 수 있어요.',
    );
    expect(card.name, '아디팜정(히드록시진염산염)');
    expect(card.purposeLabel, '가려움 완화 · 불안·긴장 완화');
    expect(card.spoken, contains('가려움'));
    expect(card.spoken, isNot(contains('처방받은 약이에요')));
  });

  test('시메티딘도 허가명과 속쓰림 설명을 쓴다', () {
    final card = resolveMyMedicineCard(
      productName: '휴온스시메티딘정200밀리그램',
      displayName: '시메티딘 (속쓰림·위·소화·알레르기)',
      ingredient: '시메티딘',
      purposeLabel: '속쓰림·위산 역류 완화',
      shortExplanation: '위산을 줄여 속쓰림과 위산 역류를 완화하는 약이에요.',
    );
    expect(card.name, '휴온스시메티딘정200밀리그램');
    expect(card.purposeLabel, '속쓰림·위산 역류 완화');
    expect(card.spoken, contains('위산을 줄여'));
  });

  test('서버 설명이 없으면 특정 약 하드코딩 문구를 만들지 않는다', () {
    final card = resolveMyMedicineCard(
      medicineCode: '197800210',
      productName: '아디팜정(히드록시진염산염)',
    );
    expect(card.spoken, isNull);
    expect(card.purposeLabel, isNull);
  });

  test('수출명만 제거하고 성분 괄호는 보존한다', () {
    expect(stripExportAlias('제품정(수출명 : TAGAMENT)(성분명)'), '제품정(성분명)');
    expect(stripExportAlias('아디팜정(히드록시진염산염)'), '아디팜정(히드록시진염산염)');
  });
}
