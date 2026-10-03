import 'package:alkong_yakong/features/medicines/domain/explanation_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서술 꼬리만 걷고 꾸미는 말은 살린다', () {
    const text = '불규칙하거나 지나치게 빠른 심장 박동을 조절하는 데 사용해요.';
    expect(
      emphasisKeyword('불규칙하거나 지나치게 빠른 심장 박동을 조절하는 데', text),
      '불규칙하거나 지나치게 빠른 심장 박동',
    );
  });

  test('뜻 없는 끝말은 걷는다', () {
    const text = '알레르기로 인한 가려움 같은 증상을 줄이는 데 사용해요.';
    expect(emphasisKeyword('알레르기로 인한 가려움 같은 증상을 줄이는 데', text), '알레르기로 인한 가려움');
  });

  test('줄인 말이 본문에 없으면 줄이지 않는다', () {
    expect(emphasisKeyword('혈압을 낮추는 데', '전혀 다른 문장이에요.'), '혈압을 낮추는 데');
  });

  test('이미 낱말이면 그대로 둔다', () {
    const text = '불안·긴장 증상을 완화해요.';
    expect(emphasisKeyword('불안·긴장', text), '불안·긴장');
  });
}
