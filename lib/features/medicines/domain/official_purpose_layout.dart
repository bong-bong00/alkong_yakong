/// Display-only structure. The official source string is never rewritten in storage.
class OfficialPurposeLayout {
  final String heading;
  final String body;

  const OfficialPurposeLayout({this.heading = '', required this.body});

  factory OfficialPurposeLayout.fromText(String raw) {
    // Only a top-level colon is a heading separator. Do not split ratios or times.
    var depth = 0;
    var separator = -1;
    var balanced = true;
    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if ('(（['.contains(char)) depth++;
      if (')）]'.contains(char)) {
        depth--;
        if (depth < 0) balanced = false;
      }
      if (depth == 0 && (char == ':' || char == '：') && separator < 0) {
        final previous = i > 0 ? raw[i - 1] : '';
        final next = i + 1 < raw.length ? raw[i + 1] : '';
        if (!(RegExp(r'\d').hasMatch(previous) &&
            RegExp(r'\d').hasMatch(next))) {
          separator = i;
        }
      }
    }
    // Ambiguous parentheses remain exactly as supplied.
    if (!balanced || depth != 0) return OfficialPurposeLayout(body: raw);
    final heading = separator > 0 ? raw.substring(0, separator + 1).trim() : '';
    final text = separator > 0 ? raw.substring(separator + 1).trim() : raw;
    final out = StringBuffer();
    depth = 0;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if ('(（['.contains(char)) {
        if (depth == 0) out.write('\n');
        depth++;
      }
      out.write(char);
      if (')）]'.contains(char)) depth--;
      // Preserve commas/semicolons and every qualification, just add line breaks.
      if ((char == ',' || char == '，' || char == ';' || char == '；') &&
          (depth == 1 || (depth == 0 && text.length > 80))) {
        final previous = i > 0 ? text[i - 1] : '';
        final next = i + 1 < text.length ? text[i + 1] : '';
        if (!(RegExp(r'\d').hasMatch(previous) &&
            RegExp(r'\d').hasMatch(next))) {
          out.write('\n');
        }
      }
    }
    return OfficialPurposeLayout(heading: heading, body: out.toString());
  }
}
