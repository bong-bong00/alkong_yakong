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

/// 짚을 말을 낱말로 줄인다.
///
/// "불규칙하거나 지나치게 빠른 심장 박동을 조절하는 데"를 통째로 파랗게
/// 하면 문장을 두 번 읽는 것과 같다. 끝의 서술("…을 조절하는 데")을 걷고,
/// 남은 말의 끝 낱말만 남긴다 — "심장 박동", "가려움".
///
/// 줄인 말이 본문에 그대로 없으면 줄이지 않는다. 화면은 본문에 있는
/// 토막만 칠할 수 있다.
String emphasisKeyword(String phrase, String text) {
  var head = phrase.trim();
  if (head.isEmpty) return phrase;
  head = head
      .replaceFirst(
        RegExp(
          r'\s*\S*(조절|완화|치료|개선|예방|억제|줄이|낮추|덜어|가라앉)\S*'
          r'(\s*(데|때|것|데에))?\s*$',
        ),
        '',
      )
      .trim();
  final words = head.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return phrase;
  var keyword = words.last.replaceFirst(
    RegExp(r'(을|를|이|가|은|는|에|의|과|와|도|만)$'),
    '',
  );
  if (keyword.isEmpty) return phrase;
  if (words.length >= 2) {
    final before = words[words.length - 2];
    // 꾸미는 말("불규칙하거나", "인한", "빠른")은 낱말이 아니다.
    final modifier = RegExp(r'(한|는|른|린|운|긴|쁜|거나|게|로|서)$').hasMatch(before);
    if (!modifier && before.length <= 4) keyword = '$before $keyword';
  }
  return text.contains(keyword) ? keyword : phrase;
}
