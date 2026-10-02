import 'package:shared_preferences/shared_preferences.dart';

/// 이미 띄워 본 "처방전 찍어 주세요" 부탁의 번호를 적어 두는 장부.
///
/// 서버에는 부탁을 처리했다는 표시가 없다. 같은 부탁으로 앱을 켤 때마다
/// 팝업이 뜨면 보호자는 창부터 닫는 버릇이 들고, 정작 새 부탁도 그렇게
/// 닫아 버린다. 그래서 이 기기에서 한 번 보여 준 번호를 적어 둔다.
///
/// 알림 목록에서는 계속 보인다 — 띄우기만 한 번 한다.
abstract final class PrescriptionHelpInbox {
  static String _key(String guardianUserId) =>
      'prescription_help_shown_$guardianUserId';

  /// 아직 안 띄워 본 번호만 돌려준다.
  static Future<List<int>> unshown(
    String guardianUserId,
    Iterable<int> ids,
  ) async {
    final owner = guardianUserId.trim();
    final wanted = ids.toSet().toList();
    if (owner.isEmpty || wanted.isEmpty) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = (prefs.getStringList(_key(owner)) ?? const <String>[])
          .toSet();
      return wanted.where((id) => !seen.contains('$id')).toList();
    } catch (_) {
      // 장부를 못 읽으면 띄우지 않는다. 같은 창을 두 번 띄우는 편보다 낫다.
      return const [];
    }
  }

  /// 이 번호들은 띄운 것으로 적어 둔다.
  static Future<void> markShown(
    String guardianUserId,
    Iterable<int> ids,
  ) async {
    final owner = guardianUserId.trim();
    final added = ids.map((id) => '$id').toList();
    if (owner.isEmpty || added.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final merged = {...?prefs.getStringList(_key(owner)), ...added}.toList();
      await prefs.setStringList(_key(owner), merged);
    } catch (_) {
      // 적지 못했다고 부탁을 못 보게 막지는 않는다.
    }
  }
}
