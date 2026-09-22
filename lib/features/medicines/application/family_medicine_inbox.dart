import 'package:shared_preferences/shared_preferences.dart';

/// 가족이 대신 넣어준 약을 어르신에게 한 번 알려주기 위한 장부.
///
/// 서버가 "누가 넣었는지"를 돌려주지 않는다. 그래서 **이 기기가 본 약 코드**를
/// 적어 두고, 다음에 켰을 때 장부에 없는 약이 있으면 내가 넣지 않은 약으로 본다.
///
/// 틀릴 수 있는 자리가 둘이라 둘 다 막아 둔다.
/// ① 내가 이 기기에서 넣은 약은 넣는 그 자리에서 [markSeen]으로 적는다.
/// ② 처음 켠 기기(장부가 아예 없는 경우)에는 아무것도 알리지 않고 지금 것을
///    전부 적어 둔다 — 로그인 첫날 "가족이 넣어드렸어요"가 뜨면 거짓말이 된다.
abstract final class FamilyMedicineInbox {
  static String _key(String userId) => 'family_inbox_seen_$userId';

  /// 장부에 없는 약 코드. 처음 켠 기기면 전부 적어 두고 빈 목록을 돌려준다.
  static Future<List<String>> unseen(
    String userId,
    Iterable<String> codes,
  ) async {
    final id = userId.trim();
    final current = _clean(codes);
    if (id.isEmpty || current.isEmpty) return const [];

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key(id));
      if (saved == null) {
        await prefs.setStringList(_key(id), current);
        return const [];
      }

      final seen = saved.toSet();
      return current.where((code) => !seen.contains(code)).toList();
    } catch (_) {
      // 장부를 못 읽으면 알리지 않는다. 확실하지 않은 채로 말을 걸지 않는다.
      return const [];
    }
  }

  /// 이 약들은 알린 것으로 (또는 내가 넣은 것으로) 적어 둔다.
  static Future<void> markSeen(String userId, Iterable<String> codes) async {
    final id = userId.trim();
    final added = _clean(codes);
    if (id.isEmpty || added.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final merged = {...?prefs.getStringList(_key(id)), ...added}.toList();
      await prefs.setStringList(_key(id), merged);
    } catch (_) {
      // 이 장부는 덧붙이다. 적지 못했다고 약 등록을 막지 않는다.
    }
  }

  static List<String> _clean(Iterable<String> codes) {
    final seen = <String>{};
    return [
      for (final raw in codes)
        if (raw.trim().isNotEmpty && seen.add(raw.trim())) raw.trim(),
    ];
  }
}
