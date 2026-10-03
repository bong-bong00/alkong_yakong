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
