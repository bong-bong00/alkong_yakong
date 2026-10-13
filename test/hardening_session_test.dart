import 'dart:async';
import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/network/api_config.dart';
import 'package:alkong_yakong/core/session/auth_session.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/session/session_credentials.dart';
import 'package:alkong_yakong/features/profile/application/session_actions.dart';
import 'package:alkong_yakong/features/profile/data/user_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/authenticated_session.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthSession.load();
  });
  tearDown(() async => AuthSession.logout());

  test('legacy preferences alone require re-login', () async {
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'userId': 'old-user',
      'role': 'patient',
    });
    await AuthSession.load();
    expect(AuthSession.isLoggedIn, isFalse);
    expect(MvpSession.userId, isEmpty);
  });

  test(
    'login credential goes to both configured servers and stays out of preferences',
    () async {
      final response = loginResponse('self');
      final loginApi = ApiClient(
        client: MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await UserRepository(
        apiClient: loginApi,
      ).login(phone: '01012345678', password: 'test123');
      for (final url in [ApiConfig.baseUrl, ApiConfig.localFeatureBaseUrl]) {
        final api = ApiClient(
          baseUrl: url,
          client: MockClient((request) async {
            expect(
              request.headers['Authorization'],
              'Bearer ${response['access_token']}',
            );
            return http.Response(
              '{}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        await api.get('/api/v1/users/self/medicines');
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((key) => key.contains('token')), isFalse);
    },
  );

  test('offline reads only own cached data, writes still fail', () async {
    await authenticatedSession('self');
    var connected = true;
    final api = ApiClient(
      client: MockClient((request) async {
        if (!connected) throw http.ClientException('offline');
        return http.Response(
          '{"medicines":[{"product_name":"내 약"}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final own = await api.get('/api/v1/users/self/medicines');
    await api.get('/api/v1/users/other/medicines');
    connected = false;
    expect(await api.get('/api/v1/users/self/medicines'), own);
    expect(SessionCredentials.offline.value, isTrue);
    await expectLater(
      api.get('/api/v1/users/other/medicines'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      api.post(
        '/api/v1/medication-logs',
        body: {'user_id': 'self', 'schedule_id': 1},
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'authorization rejection never falls back to saved health data',
    () async {
      await authenticatedSession('self');
      var status = 200;
      final api = ApiClient(
        client: MockClient(
          (request) async => http.Response(
            status == 200 ? '{"medicines":[]}' : '{"detail":"denied"}',
            status,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await api.get('/api/v1/users/self/medicines');
      status = 403;
      await expectLater(
        api.get('/api/v1/users/self/medicines'),
        throwsA(isA<ApiException>()),
      );
      expect(SessionCredentials.isValid, isTrue);
      status = 401;
      await expectLater(
        api.get('/api/v1/users/self/medicines'),
        throwsA(isA<ApiException>()),
      );
      expect(SessionCredentials.isValid, isFalse);
      expect(AuthSession.isLoggedIn, isFalse);
    },
  );

  test(
    'a healthy account server does not hide cached medication data warning',
    () async {
      await authenticatedSession('self');
      var medicationAvailable = true;
      final medication = ApiClient(
        baseUrl: ApiConfig.localFeatureBaseUrl,
        client: MockClient((_) async {
          if (!medicationAvailable) throw http.ClientException('offline');
          return http.Response(
            '{"medicines":[]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final account = ApiClient(
        baseUrl: ApiConfig.baseUrl,
        client: MockClient(
          (_) async => http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await medication.get('/api/v1/users/self/medicines');
      medicationAvailable = false;
      await medication.get('/api/v1/users/self/medicines');
      await account.get('/api/v1/users/self');
      expect(SessionCredentials.offline.value, isTrue);
      medicationAvailable = true;
      await medication.get('/api/v1/users/self/medicines');
      expect(SessionCredentials.offline.value, isFalse);
    },
  );

  test('account switch discards cache and old in-flight responses', () async {
    await authenticatedSession('first');
    final pending = Completer<http.Response>();
    final api = ApiClient(client: MockClient((_) => pending.future));
    final oldRead = api.get('/api/v1/users/first/medicines');
    final expectation = expectLater(oldRead, throwsA(isA<ApiException>()));
    await authenticatedSession('second');
    pending.complete(
      http.Response(
        '{"medicines":["first user"]}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await expectation;
    expect(SessionCredentials.userId, 'second');
    final store = await const FlutterSecureStorage().readAll();
    expect(
      store.keys.where((key) => key.startsWith('alkong_own_cache_v1_first_')),
      isEmpty,
    );
  });

  test(
    'startup offline restores only an unexpired protected profile',
    () async {
      await authenticatedSession('self');
      final repository = UserRepository(
        apiClient: ApiClient(
          client: MockClient((_) async {
            throw http.ClientException('offline');
          }),
        ),
      );
      final user = await restorePersistedSession(repository);
      expect(user?.id, 'self');
      expect(AuthSession.isLoggedIn, isTrue);
      expect(SessionCredentials.offline.value, isTrue);
      await AuthSession.logout();
      expect(await restorePersistedSession(repository), isNull);
    },
  );

  test(
    'expired protected session and cached profile cannot unlock the app',
    () async {
      final expired = loginResponse(
        'self',
        lifetime: const Duration(seconds: -1),
      );
      FlutterSecureStorage.setMockInitialValues({
        'alkong_session_v1': jsonEncode({
          'access_token': expired['access_token'],
          'profile': expired,
        }),
      });
      SharedPreferences.setMockInitialValues({
        'isLoggedIn': true,
        'userId': 'self',
      });
      await AuthSession.load();
      expect(AuthSession.isLoggedIn, isFalse);
      expect(SessionCredentials.profile, isNull);
      expect(SessionCredentials.isValid, isFalse);
    },
  );
}
