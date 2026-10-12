import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens and offline personal data stay in OS-backed encrypted storage.
abstract final class SessionCredentials {
  static const _storage = FlutterSecureStorage();
  static String? accessToken;

  static Future<void> load() async {
    try {
      accessToken = await _storage.read(key: 'session_access_token');
    } catch (_) {
      accessToken = null;
    }
  }

  static Future<void> saveToken(String token) async {
    accessToken = token;
    try {
      await _storage.write(key: 'session_access_token', value: token);
    } catch (_) {}
  }

  static Future<void> saveProfile(Map<String, dynamic> profile) async {
    final clean = Map<String, dynamic>.from(profile)
      ..remove('access_token')
      ..remove('password')
      ..remove('password_hash');
    try {
      await _storage.write(
        key: 'offline_profile_${clean['id']}',
        value: jsonEncode(clean),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> offlineProfile(String userId) async {
    try {
      final claims =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(accessToken!.split('.')[1]),
                  ),
                ),
              )
              as Map;
      if (claims['sub'] != userId ||
          (claims['exp'] as num) * 1000 <=
              DateTime.now().millisecondsSinceEpoch) {
        return null;
      }
      final raw = await _storage.read(key: 'offline_profile_$userId');
      if (raw == null) return null;
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return data['id'] == userId ? data : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    accessToken = null;
    try {
      await _storage.delete(key: 'session_access_token');
      await _storage.delete(key: 'offline_profile');
    } catch (_) {}
  }

  static bool validFor(String userId) {
    try {
      final claims =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(accessToken!.split('.')[1]),
                  ),
                ),
              )
              as Map;
      return claims['sub'] == userId &&
          (claims['exp'] as num) * 1000 > DateTime.now().millisecondsSinceEpoch;
    } catch (_) {
      return false;
    }
  }

  static Future<void> cacheResponse(String key, Object data) async {
    try {
      await _storage.write(key: 'response_$key', value: jsonEncode(data));
    } catch (_) {}
  }

  static Future<dynamic> cachedResponse(String key) async {
    try {
      final raw = await _storage.read(key: 'response_$key');
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
