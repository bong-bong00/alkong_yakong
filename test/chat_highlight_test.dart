import 'package:alkong_yakong/features/drug_explain/chat_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('얼마나·언제는 파랑 쪽으로 모은다', () {
    const reply =
        '이 약은 하루 3번, 한 번에 1알씩 식사 후에 드세요. '
        '술과 같이 드시면 안 돼요.';
    expect(chatHighlightTerms(reply), ['하루 3번', '1알', '식사 후']);
  });

  test('하지 말 것은 따로 모은다', () {
    const reply = '술과 같이 드시면 안 돼요. 빈속에 드시지 마세요. 자몽은 피하세요.';
    expect(chatWarningTerms(reply), ['같이 드시면 안 돼요', '드시지 마세요', '피하세요']);
    expect(chatHighlightTerms(reply), ['빈속']);
  });

  test('답에 없는 말은 만들지 않는다', () {
    expect(chatHighlightTerms('특별히 걸리는 것은 없었어요.'), isEmpty);
    expect(chatWarningTerms('특별히 걸리는 것은 없었어요.'), isEmpty);
    expect(chatHighlightTerms('   '), isEmpty);
  });

  test('짚을 말은 답에 그대로 있는 토막이다', () {
    const reply = '빈속에 드시지 마세요. 500mg을 넘기지 마세요.';
    for (final term in [
      ...chatHighlightTerms(reply),
      ...chatWarningTerms(reply),
    ]) {
      expect(reply.contains(term), isTrue, reason: term);
    }
  });
}
