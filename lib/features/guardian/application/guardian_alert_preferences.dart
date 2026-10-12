import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/session/mvp_session.dart';

abstract final class GuardianAlertPreferences {
  static const defaults = {
    'guardian_alert_in_app': true,
    'guardian_alert_missed': true,
    'guardian_alert_heart': true,
    'guardian_alert_new_medicine': true,
  };
  static String key(String name) => '${name}_${MvpSession.userId}';
  static Future<Map<String, bool>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        for (final entry in defaults.entries)
          entry.key:
              prefs.getBool(key(entry.key)) ??
              prefs.getBool(entry.key) ??
              (entry.key == 'guardian_alert_in_app'
                  ? prefs.getBool('guardian_alert_push')
                  : null) ??
              entry.value,
      };
    } catch (_) {
      return Map.of(defaults);
    }
  }

  static bool allows(Map<String, bool> prefs, String kind) =>
      prefs['guardian_alert_in_app'] != false &&
      (kind != 'miss' || prefs['guardian_alert_missed'] != false) &&
      (kind != 'alert' || prefs['guardian_alert_heart'] != false) &&
      (kind != 'prescription' || prefs['guardian_alert_new_medicine'] != false);
}
