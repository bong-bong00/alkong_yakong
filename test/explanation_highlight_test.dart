import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/features/medicines/domain/explanation_highlight.dart';

void main() {
  test(
    'displayed short explanation falls back to matching treatment title',
    () {
      const text = '알레르기로 인한 가려움 같은 증상을 줄이는 데 사용해요.';
      expect(
        explanationHighlight(text, [
          '가려움과 불안·긴장 증상을 완화하는 데 도움을 줘요.',
          '공식 허가정보에서 확인한 대표 사용 목적이에요.',
          '알레르기로 인한 가려움',
        ]),
        '알레르기로 인한 가려움',
      );
    },
  );
  test('missing phrases and whole body never become guessed highlights', () {
    expect(explanationHighlight('설명 전체', ['없는 구절', '설명 전체']), '');
    expect(explanationHighlight('심장 박동을 조절해요.', ['심장 박동']), '심장 박동');
  });
}
