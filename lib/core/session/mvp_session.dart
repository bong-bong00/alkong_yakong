abstract final class MvpSession {
  static const String _definedUserId = String.fromEnvironment('USER_ID');

  static String userId = _definedUserId;
  static String medicineCode = '';
  static List<Map<String, dynamic>> latestOcrItems = <Map<String, dynamic>>[];
  static DateTime? latestOcrRegisteredAt;
}
