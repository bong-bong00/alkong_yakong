abstract final class MvpSession {
  static const String _definedUserId = String.fromEnvironment('USER_ID');

  /// 서버 오늘약 API용. dart-define 없으면 체험 사용자.
  static String userId =
      _definedUserId.isNotEmpty ? _definedUserId : 'mvp-user';
  static String medicineCode = '';
  static List<Map<String, dynamic>> latestOcrItems = <Map<String, dynamic>>[];
  static DateTime? latestOcrRegisteredAt;
}
