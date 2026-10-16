import '../../../core/network/api_client.dart';
import '../../../core/session/session_credentials.dart';
import '../domain/user_profile.dart';

/// 가입 · 로그인 · 내 정보 읽기/고치기 · 탈퇴.
class UserRepository {
  UserRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  static String _path(String userId) =>
      '/api/v1/users/${Uri.encodeComponent(userId)}';

  Future<UserProfile> fetch(String userId) async {
    final response = await _api.get(_path(userId));
    final user = _profile(response);
    await SessionCredentials.updateProfile(
      Map<String, dynamic>.from(response as Map),
    );
    return user;
  }

  Future<UserProfile> signUp(Map<String, dynamic> body) async =>
      _authenticatedProfile(await _api.post('/api/v1/users', body: body));

  Future<UserProfile> login({
    required String phone,
    required String password,
  }) async => _authenticatedProfile(
    await _api.post(
      '/api/v1/users/login',
      body: {'phone': phone, 'password': password},
    ),
  );

  Future<UserProfile> update(
    String userId,
    Map<String, dynamic> changes,
  ) async {
    final response = await _api.patch(_path(userId), body: changes);
    final user = _profile(response);
    await SessionCredentials.updateProfile(
      Map<String, dynamic>.from(response as Map),
    );
    return user;
  }

  Future<void> delete(String userId) => _api.delete(_path(userId));

  Future<void> changePassword(
    String userId, {
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api.post(
      '${_path(userId)}/password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  static Future<UserProfile> _authenticatedProfile(dynamic response) async {
    final user = _profile(response);
    try {
      await SessionCredentials.install(
        Map<String, dynamic>.from(response as Map),
      );
    } catch (_) {
      throw const ApiException('로그인 정보를 안전하게 저장하지 못했어요. 다시 로그인해 주세요.');
    }
    return user;
  }

  static UserProfile _profile(dynamic response) {
    if (response is Map) {
      final data = Map<String, dynamic>.from(response);
      final id = data['id']?.toString().trim() ?? '';
      final role = data['role']?.toString().trim().toLowerCase();
      if (id.isNotEmpty &&
          id != 'mvp-user' &&
          (role == 'patient' || role == 'guardian')) {
        return UserProfile.fromJson(data);
      }
    }
    throw const ApiException('서버에서 내 정보를 받지 못했어요.');
  }
}
