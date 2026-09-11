/// 홈·목록·상세·기록·알림에 공통으로 쓰는 표시 규칙.
library;

const _placeholderSpoken = '처방받은 약이에요';

const _spokenAliases = <String, String>{
  '피를 묽게 하는 약이에요': '피가 굳지 않게 하는 약이에요',
  '피를 묽게 하는 약이에요.': '피가 굳지 않게 하는 약이에요',
};

const _easyLabelAliases = <String, String>{
  '피 묽게 하는 약': '피가 굳지 않게 하는 약',
  '피 묽게': '피가 굳지 않게 하는 약',
  '피를 묽게 하는 약': '피가 굳지 않게 하는 약',
  '혈압 낮춤': '혈압약',
  '혈당 조절': '당뇨약',
};

final _permissionNameHint = RegExp(r'(정|캡슐|캅셀|액|시럽|연고|밀리그램|밀리그람)');
final _exportAliasParen = RegExp(
  r'\s*\((?:수출\s*명\s*[:：]?|수출\s*용|수출용\s*별칭)[^)]*\)',
  caseSensitive: false,
);

class MyMedicineCard {
  final String name;
  final String? purposeLabel;
  final String? spoken;

  const MyMedicineCard({required this.name, this.purposeLabel, this.spoken});
}

String normalizeEasyLabel(String? label) {
  final text = (label ?? '').trim();
  return _easyLabelAliases[text] ?? text;
}

/// 서버 버전이 오래되어도 수출용 별칭은 화면에 노출하지 않는다.
String stripExportAlias(String? name) {
  final text = (name ?? '').trim();
  if (text.isEmpty) return '';
  return text
      .replaceAll(_exportAliasParen, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String stripEasyCategoryParen(String? name) {
  final text = stripExportAlias(name);
  final match = RegExp(r'\s*\(([^)]*)\)\s*$').firstMatch(text);
  if (match == null) return text;
  final inner = match.group(1)?.trim() ?? '';
  if (_isCategoryParen(inner)) {
    return text.substring(0, match.start).trim();
  }
  return text;
}

bool _isCategoryParen(String inner) {
  final text = normalizeEasyLabel(inner);
  if (text.contains('·') || text.contains(',')) return true;
  if (isCardPurposeLabel(text)) return true;
  return inner.contains('묽게') ||
      inner.contains('낮춤') ||
      inner.contains('조절') ||
      inner.contains('속쓰림') ||
      inner.contains('알레르기') ||
      inner.contains('두통');
}

bool isMockDrugInfoName(String? name) {
  final compact = stripEasyCategoryParen(
    name,
  ).replaceAll(RegExp(r'\s+'), '').toLowerCase();
  return compact == '아스피린100mg' ||
      compact == '암로디핀5mg' ||
      compact == '메트포르민500mg';
}

bool looksLikePermissionProductName(String? name) {
  final text = stripEasyCategoryParen(name);
  if (text.isEmpty) return false;
  return _permissionNameHint.hasMatch(text);
}

/// 카드 제목은 허가 제품명. 성분+키워드 괄호는 제목으로 쓰지 않는다.
String cardOfficialName({
  String? productName,
  String? displayName,
  String? ingredient,
}) {
  final candidates = <String?>[productName, displayName, ingredient];
  for (final raw in candidates) {
    final stripped = stripEasyCategoryParen(raw);
    if (stripped.isEmpty) continue;
    if (looksLikePermissionProductName(raw) ||
        looksLikePermissionProductName(stripped)) {
      return stripped;
    }
  }
  for (final raw in candidates) {
    final stripped = stripEasyCategoryParen(raw);
    if (stripped.isNotEmpty) return stripped;
  }
  return '약';
}

/// 짧은 분류로 쓸 수 있는 쉬운말인지. 증상 키워드 나열은 false.
bool isCardPurposeLabel(String? label) {
  final text = normalizeEasyLabel(label);
  if (text.isEmpty) return false;
  if (text.contains('완화') || text.contains('약이에요')) return true;
  if (text.endsWith('약') || text.endsWith('제') || text.contains('하는 약')) {
    return true;
  }
  return false;
}

String? cardPurposeLabel(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final parts = text
      .split(' · ')
      .map(normalizeEasyLabel)
      .where((part) => part.isNotEmpty && isCardPurposeLabel(part))
      .toList();
  final unique = <String>[];
  for (final part in parts) {
    if (!unique.contains(part)) unique.add(part);
  }
  if (unique.isEmpty) return null;
  return unique.join(' · ');
}

String? cardSpokenOf(String? text) {
  var value = (text ?? '').trim();
  value = _spokenAliases[value] ?? value;
  if (value.isEmpty || value == _placeholderSpoken) return null;
  return value;
}

/// 긴 복합제 성분은 카드에서 첫 성분과 나머지 개수만 보여 준다.
/// 원문은 모델에 그대로 보존하므로 상세 화면에서는 전체 성분을 쓸 수 있다.
List<String> ingredientParts(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return const [];
  final parts = text
      .split(RegExp(r'[|;\n\r]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  final unique = <String>[];
  for (final part in parts) {
    if (!unique.contains(part)) unique.add(part);
  }
  return unique;
}

String compactIngredientSummary(String? raw) {
  final parts = ingredientParts(raw);
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  return '${parts.first} 외 ${parts.length - 1}개';
}

/// 홈·목록·상세·기록·알림이 같은 이름·설명을 쓰게 한곳에서 고른다.
MyMedicineCard resolveMyMedicineCard({
  String? medicineCode,
  String? productName,
  String? displayName,
  String? ingredient,
  String? purposeLabel,
  String? shortExplanation,
  String? easyCategory,
}) {
  final name = cardOfficialName(
    productName: productName,
    displayName: displayName,
    ingredient: ingredient,
  );
  var purpose = cardPurposeLabel(purposeLabel);
  var spoken = cardSpokenOf(shortExplanation) ?? cardSpokenOf(easyCategory);
  return MyMedicineCard(name: name, purposeLabel: purpose, spoken: spoken);
}
