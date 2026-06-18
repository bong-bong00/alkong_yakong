import 'package:shared_preferences/shared_preferences.dart';

/// 로그인 유지용 간단 세션.
/// 앱을 껐다 켜도 로그인 상태가 유지되도록 SharedPreferences에 저장한다.
class AuthSession {
  static bool isLoggedIn = false;
  static String role = 'patient'; // patient | guardian
  static SharedPreferences? _prefs;

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    isLoggedIn = _prefs?.getBool('isLoggedIn') ?? false;
    role = _prefs?.getString('role') ?? 'patient';
  }

  static Future<void> setLoggedIn(String r) async {
    isLoggedIn = true;
    role = r;
    await _prefs?.setBool('isLoggedIn', true);
    await _prefs?.setString('role', r);
  }

  static Future<void> logout() async {
    isLoggedIn = false;
    await _prefs?.setBool('isLoggedIn', false);
  }
}
