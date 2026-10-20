import 'session_credentials.dart';

abstract final class OfflineStatus {
  static final active = SessionCredentials.offline;
  static void cached(String path) {
    SessionCredentials.markUnavailable('', path);
  }

  static void fresh(String path) {
    SessionCredentials.markAvailable('', path);
  }

  static void clear() {
    active.value = false;
  }
}
