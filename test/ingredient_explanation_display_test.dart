import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/features/medicines/domain/ingredient_explanation_display.dart';

void main() {
  test('약 이름이나 특정 효능과 무관하게 소개 뒤 핵심 설명을 바로 표시한다', () {
    for (final sample in [
      ('아미오다론염산염', '전기 신호를 조절해요.', '불규칙한 심장 박동을 조절하는 데 도움을 줘요.'),
      ('히드록시진염산염', '몸의 알레르기 반응에 작용해요.', '가려움 같은 증상을 줄이는 데 도움을 줘요.'),
      ('시메티딘', '위산 분비에 작용해요.', '위산으로 인한 속쓰림을 줄이는 데 도움을 줘요.'),
      ('프레드니카르베이트', '피부의 염증 반응에 작용해요.', '피부 가려움 같은 증상을 줄이는 데 도움을 줘요.'),
    ]) {
      final intro = '${sample.$1}은 이 약의 주성분으로,';
      final text = '$intro ${sample.$2} ${sample.$3} 별도 주의 안내.';
      expect(
        ingredientExplanationDisplay(text, sample.$3),
        '$intro ${sample.$3} 별도 주의 안내.',
      );
    }
  });

  test('핵심 설명이 없거나 원문에 없으면 내용을 자르지 않는다', () {
    const text = '성분은 이 약의 주성분으로, 역할과 사용 목적을 설명해요.';
    expect(ingredientExplanationDisplay(text, ''), text);
    expect(ingredientExplanationDisplay(text, '없는 설명'), text);
    expect(ingredientExplanationDisplay('다른 형식의 설명', '설명'), '다른 형식의 설명');
  });

  test('이미 간결한 설명은 그대로 유지한다', () {
    const text = '성분은 이 약의 주성분으로, 핵심 설명이에요.';
    expect(ingredientExplanationDisplay(text, '핵심 설명이에요.'), text);
  });
}
