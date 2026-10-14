import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credentials and own-user read cache stay in the platform's protected store.
/// They are never persisted in SharedPreferences or printed to logs.
abstract final class SessionCredentials {
  static const _storage = FlutterSecureStorage();
  static const _sessionKey = 'alkong_session_v1';
  static const _cachePrefix = 'alkong_own_cache_v1_';
  static final changes = ValueNotifier<int>(0);
  static final offline = ValueNotifier<bool>(false);
  static final Set<String> _unavailableReads = <String>{};
  static Future<void> Function()? onCleared;
  static String? _token;
  static String? userId;
  static String? role;
  static DateTime? expiresAt;
  static Map<String, dynamic>? profile;
  static Timer? _expiryTimer;
  static Future<void> _pendingWrite = Future<void>.value();
  static int generation = 0;

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pendingWrite.then((_) => action());
    _pendingWrite = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  static bool get isValid =>
      _token != null &&
      userId != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());

  static String? get accessToken => isValid ? _token : null;

  static void markUnavailable(String origin, String path) {
    if (!isValid) return;
    _unavailableReads.add('$origin$path');
    offline.value = true;
  }

  static void markAvailable(String origin, String path) {
    _unavailableReads.remove('$origin$path');
    offline.value = _unavailableReads.isNotEmpty;
  }

  static Map<String, dynamic> _claims(String token) {
    final parts = token.split('.');
    if (parts.length != 2) throw const FormatException('Credential format');
    return Map<String, dynamic>.from(
      jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts.first))),
          )
          as Map,
    );
  }

  static bool _readSession(Map<String, dynamic> data) {
    final token = data['access_token'];
    final user = data['profile'];
    if (token is! String || user is! Map) return false;
    final claims = _claims(token);
    final id = user['id'];
    final userRole = user['role']?.toString().toLowerCase();
    final expiry = claims['exp'];
    if (id is! String ||
        id.isEmpty ||
        expiry is! int ||
        claims['sub'] != id ||
        claims['role'] != userRole ||
        claims['kind'] != 'access' ||
        claims['aud'] != 'alkong-yakong' ||
        !const ['patient', 'guardian'].contains(userRole)) {
      return false;
    }
    final until = DateTime.fromMillisecondsSinceEpoch(
      expiry * 1000,
      isUtc: true,
    );
    if (!until.isAfter(DateTime.now())) return false;
    _token = token;
    userId = id;
    role = userRole;
    expiresAt = until;
    profile = Map<String, dynamic>.from(user);
    _expiryTimer?.cancel();
    _expiryTimer = Timer(
      until.difference(DateTime.now()),
      () => unawaited(clear()),
    );
    return true;
  }

  static Future<bool> load() async {
    generation++;
    await _pendingWrite;
    _expiryTimer?.cancel();
    _token = null;
    userId = null;
    role = null;
    expiresAt = null;
    profile = null;
    try {
      final raw = await _storage.read(key: _sessionKey);
      if (raw == null) return false;
      if (_readSession(Map<String, dynamic>.from(jsonDecode(raw) as Map))) {
        return true;
      }
    } catch (_) {
      // An unavailable/corrupt protected store cannot restore authentication.
    }
    await clear();
    return false;
  }

  static Future<void> install(Map<String, dynamic> response) async {
    final user = Map<String, dynamic>.from(response)
      ..remove('access_token')
      ..remove('token_type')
      ..remove('expires_in');
    final data = {'access_token': response['access_token'], 'profile': user};
    final previous = userId;
    // Validate before replacing a previous account's session.
    final token = response['access_token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Login credential is missing');
    }
    final claims = _claims(token);
    if (claims['sub'] != user['id'] ||
        claims['role'] != user['role']?.toString().toLowerCase()) {
      throw const FormatException('Login identity mismatch');
    }
    await clear();
    if (!_readSession(data)) {
      throw const FormatException('Login credential expired');
    }
    final expectedGeneration = generation;
    try {
      await _serialize(() async {
        if (generation != expectedGeneration || !isValid) {
          throw const FormatException('Session changed');
        }
        await _storage.write(key: _sessionKey, value: jsonEncode(data));
      });
    } catch (_) {
      await clear();
      rethrow;
    }
    generation++;
    offline.value = false;
    changes.value++;
    if (previous != null && previous != userId) await _deleteCache(previous);
  }

  static Future<void> updateProfile(Map<String, dynamic> value) async {
    final expectedGeneration = generation;
    try {
      await _serialize(() async {
        if (generation != expectedGeneration ||
            !isValid ||
            value['id'] != userId) {
          return;
        }
        profile = Map<String, dynamic>.from(value);
        await _storage.write(
          key: _sessionKey,
          value: jsonEncode({'access_token': _token, 'profile': profile}),
        );
      });
    } catch (_) {
      // Keep an online profile visible even if updating the cache fails.
    }
  }

  static bool canCache(String path) {
    if (!isValid) return false;
    final uri = Uri.parse(path);
    final parts = uri.pathSegments;
    return parts.length >= 4 &&
        parts[0] == 'api' &&
        parts[1] == 'v1' &&
        parts[2] == 'users' &&
        parts[3] == userId;
  }

  static String _cacheKey(String origin, String path) =>
      '$_cachePrefix${Uri.encodeComponent(userId!)}_${base64Url.encode(utf8.encode('$origin$path'))}';

  static Future<void> cacheRead(
    String origin,
    String path,
    dynamic data,
    int requestGeneration,
  ) async {
    if (generation != requestGeneration || !canCache(path)) return;
    final key = _cacheKey(origin, path);
    final encoded = jsonEncode(data);
    if (encoded.length > 500000) return;
    try {
      await _serialize(() async {
        if (generation != requestGeneration || !isValid) return;
        await _storage.write(key: key, value: encoded);
      });
    } catch (_) {
      // A cache failure must not turn a successful online read into an error.
    }
  }

  static Future<dynamic> cachedRead(
    String origin,
    String path,
    int requestGeneration,
  ) async {
    if (generation != requestGeneration || !canCache(path)) return null;
    try {
      final raw = await _storage.read(key: _cacheKey(origin, path));
      if (generation != requestGeneration || !isValid || raw == null) {
        return null;
      }
      markUnavailable(origin, path);
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteCache(String id) async {
    final prefix = '$_cachePrefix${Uri.encodeComponent(id)}_';
    final values = await _storage.readAll();
    for (final key in values.keys.where((key) => key.startsWith(prefix))) {
      await _storage.delete(key: key);
    }
  }

  static Future<void> clear() async {
    final previous = userId;
    generation++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _token = null;
    userId = null;
    role = null;
    expiresAt = null;
    profile = null;
    _unavailableReads.clear();
    offline.value = false;
    changes.value++;
    await onCleared?.call();
    try {
      await _serialize(() async {
        await _storage.delete(key: _sessionKey);
        if (previous != null) await _deleteCache(previous);
      });
    } catch (_) {
      // The session metadata callback also disables persisted login restoration.
    }
  }
}
