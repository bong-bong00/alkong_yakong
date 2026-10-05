/// 표가 한 줄로 뭉개져 목차만 앞에 몰린 용법을 푼다.
///
/// 허가 원문 표를 글로 옮기면 "○ 성인 1. 정신과 영역 2. 피부과 영역 고령자
/// 이 약은 … 성인: 1일 50㎎ … 성인: 1일 30-60㎎ …"처럼 칸 이름이 먼저
/// 늘어서고 내용이 뒤에 온다. 그대로 두면 "○ 성인 / 1. 정신과 영역"만 보이고
/// 정작 몇 ㎎인지는 접힌 아래에 숨는다. 앞의 빈 목차를 떼고, 뒤에 오는
/// "성인:"에 목차 순서대로 이름을 붙인다("성인(정신과 영역):").
///
/// 목차 수와 "성인:" 수가 같을 때만 고친다. 하나라도 어긋나면 어느 내용이
/// 어느 칸 것인지 알 수 없으니 원문을 그대로 둔다.
String untangleUsageOutline(String raw) {
  final text = raw.trim();
  final outline = RegExp(
    r'^[○●•]\s*성인\s+((?:\d+\.\s*[가-힣]+(?:\s[가-힣]+)?\s+)+)',
  ).firstMatch(text);
  if (outline == null) return raw;
  final names = RegExp(r'\d+\.\s*([가-힣]+(?:\s[가-힣]+)?)')
      .allMatches(outline.group(1)!)
      .map((match) => match.group(1)!.trim())
      .toList();
  var rest = text.substring(outline.end);
  final adults = RegExp(r'성인\s*[:：]').allMatches(rest).toList();
  if (names.length < 2 || adults.length != names.length) return raw;
  for (var i = adults.length - 1; i >= 0; i--) {
    rest = rest.replaceRange(
      adults[i].start,
      adults[i].end,
      '성인(${names[i]}):',
    );
  }
  // 목차 끝의 "고령자"가 바로 뒤 문장의 칸 이름으로 남는다. 다른 칸처럼
  // 쌍점을 붙인다.
  return rest.replaceFirst(RegExp(r'^고령자\s+(?=이 약)'), '고령자: ');
}

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
