/// Compact the standardized introduction + role + highlighted benefit layout.
/// This is presentation only: source text, warnings and the trailing text stay
/// unchanged. Without an identifiable intro/highlight, do not guess what to cut.
String ingredientExplanationDisplay(String text, String highlight) {
  final effect = highlight.trim();
  if (effect.isEmpty) return text;
  final start = text.indexOf(effect);
  if (start < 0) return text;
  final intro = RegExp(r'이 약의 주성분으로\s*[,，]').firstMatch(text);
  if (intro == null || intro.end >= start) return text;
  return '${text.substring(0, intro.end)} ${text.substring(start)}';
}
