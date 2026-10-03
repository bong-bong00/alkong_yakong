/// Highlight only a source-provided phrase actually present in the shown text.
String explanationHighlight(String text, Iterable<String> candidates) {
  for (final candidate in candidates) {
    final phrase = candidate.trim();
    if (phrase.isNotEmpty && phrase != text.trim() && text.contains(phrase)) {
      return phrase;
    }
  }
  return '';
}

/// 짚을 말에서 서술 꼬리를 걷는다.
///
/// 문장을 통째로 파랗게 하면 문장을 두 번 읽는 것과 같다. 그렇다고
/// 낱말 하나만 남기면("심장 박동") 어떤 심장 박동인지가 빠진다.
/// 꾸미는 말까지는 살리고, 뒤에 붙은 서술만 걷는다 —
/// "불규칙하거나 지나치게 빠른 심장 박동을 조절하는 데"
///   → "불규칙하거나 지나치게 빠른 심장 박동".
///
/// 줄인 말이 본문에 그대로 없으면 줄이지 않는다. 화면은 본문에 있는
/// 토막만 칠할 수 있다.
String emphasisKeyword(String phrase, String text) {
  var head = phrase.trim();
  if (head.isEmpty) return phrase;
  // "…을 조절하는 데", "…를 줄이는 데" 같은 뒷말을 걷는다.
  head = head
      .replaceFirst(
        RegExp(
          r'\s*\S*(조절|완화|치료|개선|예방|억제|줄이|낮추|덜어|가라앉|쓰이|사용)\S*'
          r'(\s*(데|데에|때|것))?\s*$',
        ),
        '',
      )
      .trim();
  // 끝에 남은 조사를 뗀다.
  head = head.replaceFirst(RegExp(r'(을|를|이|가|은|는|에|의|과|와|도|만)$'), '').trim();
  // "…가려움 같은 증상"처럼 뜻 없는 끝말은 걷는다.
  head = head.replaceFirst(RegExp(r'\s*(같은|등의|등)?\s*(증상|상태|경우)$'), '').trim();
  if (head.isEmpty) return phrase;
  return text.contains(head) ? head : phrase;
}
