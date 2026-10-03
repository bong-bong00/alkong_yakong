/// Reorder explicit target groups without changing their instructions.
String orderOfficialUsageSections(String formattedUsage) {
  // Remove only the redundant leading tablet-form title. Do not remove form
  // headings inside the text, which may distinguish different dosing rules.
  final text = formattedUsage
      .trim()
      .replaceFirst(RegExp(r'^\(\s*정제\s*\)\s*'), '')
      .trim();
  final headings = RegExp(
    r'^[ \t]*(?:[○●•·\-]\s*|\d+[.)]\s*)?(고령자|성인|소아|어린이|유아|영아|신기능부전 환자|신기능 저하 환자|간기능 저하 환자)(?:\s*[:：]|(?=\s+이 약은))',
    multiLine: true,
  ).allMatches(text).toList();
  if (headings.length < 2) return text;
  final sections = <({String text, int priority, int index})>[];
  for (var i = 0; i < headings.length; i++) {
    final priority = switch (headings[i].group(1)!) {
      '고령자' => 0,
      '성인' => 1,
      '소아' || '어린이' || '유아' || '영아' => 2,
      _ => 3,
    };
    sections.add((
      text: text
          .substring(
            headings[i].start,
            i + 1 < headings.length ? headings[i + 1].start : text.length,
          )
          .trim(),
      priority: priority,
      index: i,
    ));
  }
  sections.sort((a, b) {
    final order = a.priority.compareTo(b.priority);
    return order != 0 ? order : a.index.compareTo(b.index);
  });
  final intro = text.substring(0, headings.first.start).trim();
  return [
    if (intro.isNotEmpty) intro,
    ...sections.map((s) => s.text),
  ].join('\n\n');
}
