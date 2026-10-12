import '../../../core/network/api_client.dart';
import '../domain/user_profile.dart';
import '../../../core/session/session_credentials.dart';
import '../../../core/session/offline_status.dart';

/// 가입 · 로그인 · 내 정보 읽기/고치기 · 탈퇴.
class UserRepository {
  UserRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  static String _path(String userId) =>
      '/api/v1/users/${Uri.encodeComponent(userId)}';

  Future<UserProfile> fetch(String userId) async {
    try {
      final profile = await _remember(await _api.get(_path(userId)));
      OfflineStatus.fresh('profile:$userId');
      return profile;
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      final cached = await SessionCredentials.offlineProfile(userId);
      if (cached == null) rethrow;
      OfflineStatus.cached('profile:$userId');
      return _profile(cached);
    }
  }

  Future<UserProfile> signUp(Map<String, dynamic> body) async =>
      _remember(await _api.post('/api/v1/users', body: body));

  Future<UserProfile> login({
    required String phone,
    required String password,
  }) async => _remember(
    await _api.post(
      '/api/v1/users/login',
      body: {'phone': phone, 'password': password},
    ),
  );

  Future<UserProfile> update(
    String userId,
    Map<String, dynamic> changes,
  ) async => _remember(await _api.patch(_path(userId), body: changes));

  static Future<UserProfile> _remember(dynamic response) async {
    final profile = _profile(response);
    final data = Map<String, dynamic>.from(response as Map);
    final token = data['access_token']?.toString();
    if (token?.isNotEmpty == true) await SessionCredentials.saveToken(token!);
    await SessionCredentials.saveProfile(data);
    return profile;
  }

  Future<void> delete(String userId) => _api.delete(_path(userId));

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
