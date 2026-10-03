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
    // 보기용 약(코다론정)을 로그인할 때마다 심지 않는다. 처방전을 넣은
    // 적 없는 분의 "내 약"에 모르는 약이 들어가 있으면, 그 약을 드셔야
    // 하는 줄 아신다. 심는 길은 아래에 남겨 두되 스스로 돌지 않는다.
    _prefs ??= await SharedPreferences.getInstance();
    isLoggedIn = true;
    role = r;
    await _prefs?.setBool('isLoggedIn', true);
    await _prefs?.setString('role', r);
    if (MvpSession.userId.isNotEmpty) {
      await _prefs?.setString('userId', MvpSession.userId);
    }
  }

  /// 보기용 약 한 가지(코다론정)를 서버에 심는다.
  ///
  /// 시연에서 함께먹기(DUR) 충돌을 보여 주려고 둔 길이다. 스스로 돌지
  /// 않는다 — 부르는 쪽에서 체험 계정에만 쓴다. 쓰는 분의 계정에
  /// 넣으면 처방받지도 않은 약을 드시게 된다.
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

  /// 스스로 나가신 분을 개발용 자동 로그인이 다시 끌고 들어오지
  /// 않게 막는 표시. 다시 로그인하시면 풀린다.
  static const String _devAutoLoginBlockedKey = 'devAutoLoginBlocked';

  static Future<bool> get devAutoLoginBlocked async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs?.getBool(_devAutoLoginBlockedKey) ?? false;
  }

  static Future<void> allowDevAutoLogin() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.remove(_devAutoLoginBlockedKey);
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
    _prefs ??= await SharedPreferences.getInstance();
    // 나가셨으면 다음에 켤 때 로그인 화면이 떠야 한다. 개발 빌드가
    // 체험 계정으로 다시 들어가 버리면 나간 것이 아니다.
    await _prefs?.setBool(_devAutoLoginBlockedKey, true);
    isLoggedIn = false;
    role = 'patient';
    await _prefs?.setBool('isLoggedIn', false);
    await _prefs?.remove('userId');
    await _prefs?.remove('role');
    MvpSession.userId = '';
    MvpSession.isPregnant = null;
  }
}
