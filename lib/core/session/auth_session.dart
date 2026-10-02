import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../network/api_config.dart';
import 'mvp_session.dart';

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
    final savedUserId = _prefs?.getString('userId');
    if (savedUserId != null && savedUserId.isNotEmpty) {
      MvpSession.userId = savedUserId;
    }
  }

  static Future<void> setLoggedIn(String r) async {
    // Presentation data must live on the medication server to enter real DUR.
    // Do not add it to release builds or to guardian accounts.
    if (kDebugMode && r == 'patient' && MvpSession.userId.isNotEmpty) {
      await ensurePresentationMedicine();
    }
    _prefs ??= await SharedPreferences.getInstance();
    isLoggedIn = true;
    role = r;
    await _prefs?.setBool('isLoggedIn', true);
    await _prefs?.setString('role', r);
    if (MvpSession.userId.isNotEmpty) {
      await _prefs?.setString('userId', MvpSession.userId);
    }
  }

  /// Runs before the first screen, even without login or signup.
  /// Keep this startup hook when replacing authentication with a demo bypass.
  static Future<void> ensurePresentationMedicine({ApiClient? apiClient}) async {
    if (!kDebugMode) return;
    if (MvpSession.userId.trim().isEmpty) {
      MvpSession.userId = MvpSession.defaultUserId;
    }
    try {
      await (apiClient ?? ApiClient(baseUrl: ApiConfig.localFeatureBaseUrl)).post(
        '/api/v1/users/${Uri.encodeComponent(MvpSession.userId)}/presentation-medicine',
        body: const {},
        timeout: const Duration(seconds: 15),
        headers: const {'X-Presentation-Mode': 'debug'},
      );
    } catch (error) {
      // Registration is server-backed; do not pretend it succeeded offline.
      debugPrint('[PRESENTATION_SEED] 코다론정 등록 실패: $error');
    }
  }

  static Future<void> persistUserId(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) return;
    _prefs ??= await SharedPreferences.getInstance();
    MvpSession.userId = normalized;
    await _prefs?.setString('userId', normalized);
  }

  static Future<bool> hasValidBackendUser(ApiClient apiClient) async {
    final userId = MvpSession.userId.trim();
    if (userId.isEmpty || userId == 'mvp-user') return false;
    try {
      final response = await apiClient.get(
        '/api/v1/users/${Uri.encodeComponent(userId)}',
      );
      return response is Map && response['id']?.toString() == userId;
    } catch (_) {
      return false;
    }
  }

  static Future<void> logout() async {
    isLoggedIn = false;
    role = 'patient';
    await _prefs?.setBool('isLoggedIn', false);
    await _prefs?.remove('userId');
    await _prefs?.remove('role');
    MvpSession.userId = '';
    MvpSession.isPregnant = null;
  }
}
