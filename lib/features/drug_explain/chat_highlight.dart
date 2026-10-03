/// 상담 답에서 짚을 말을 고른다.
///
/// 지어내지 않는다. 답에 **그대로 있는** 토막만 돌려주고, 화면은 그
/// 토막만 파랗게 칠한다. 서버가 짚을 말을 주는 것은 건강 주의 답뿐이고
/// (health_highlight_terms), 나머지 답에서는 약 이름만 짚여 왔다.
///
/// 어르신이 답에서 놓치면 안 되는 것은 세 가지다 — 얼마나, 언제,
/// 하지 말아야 할 것. 그 세 가지만 짚는다. 많이 짚으면 짚지 않은 것과
/// 같아진다.
library;

final List<RegExp> _patterns = [
  // 얼마나 — "하루 3번", "한 번에 2알", "500mg"
  RegExp(r'하루\s*\d+\s*번'),
  RegExp(r'\d+(?:\.\d+)?\s*(?:알|정|포|캡슐|방울|mg|밀리그램)'),
  // 언제 — 식사와의 사이, 자기 전
  RegExp(r'식사\s*(?:직후|후|전)'),
  RegExp(r'식후|식전|빈속|공복'),
  RegExp(r'자기\s*전'),
  // 하지 말아야 할 것
  RegExp(r'(?:같이\s*)?(?:드시면|복용하면|함께\s*드시면)\s*안\s*(?:돼요|됩니다)'),
  RegExp(r'(?:드시지|복용하지)\s*(?:마세요|말아\s*주세요)'),
  RegExp(r'피하(?:세요|셔야\s*해요|시는\s*것이\s*좋아요)'),
];

/// 답에서 짚을 토막들. 앞에서부터 찾은 차례로 돌려준다.
List<String> chatHighlightTerms(String reply) {
  final text = reply.trim();
  if (text.isEmpty) return const [];
  final found = <({int at, String text})>[];
  for (final pattern in _patterns) {
    for (final match in pattern.allMatches(text)) {
      final piece = match.group(0)?.trim() ?? '';
      if (piece.isEmpty) continue;
      found.add((at: match.start, text: piece));
    }
  }
  found.sort((left, right) => left.at.compareTo(right.at));
  final terms = <String>[];
  for (final item in found) {
    if (!terms.contains(item.text)) terms.add(item.text);
  }
  return terms;
}
