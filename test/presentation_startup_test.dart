import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/auth_session.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';

void main() {
  tearDown(() {
    MvpSession.userId = MvpSession.defaultUserId;
    AuthSession.isLoggedIn = false;
  });

  test('startup registers default medicine without login', () async {
    MvpSession.userId = '';
    AuthSession.isLoggedIn = false;
    var requests = 0;
    final api = ApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        requests++;
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/v1/users/${MvpSession.defaultUserId}/presentation-medicine',
        );
        expect(request.headers['X-Presentation-Mode'], 'debug');
        return http.Response(jsonEncode({'presentation': true}), 200);
      }),
    );
    await AuthSession.ensurePresentationMedicine(apiClient: api);
    expect(requests, 1);
    expect(MvpSession.userId, MvpSession.defaultUserId);
    // Registering demonstration medicines does not bypass authentication.
    expect(AuthSession.isLoggedIn, false);
  });

  test('startup keeps an already selected user', () async {
    MvpSession.userId = 'selected-user';
    final api = ApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/api/v1/users/selected-user/presentation-medicine',
        );
        return http.Response('{}', 200);
      }),
    );
    await AuthSession.ensurePresentationMedicine(apiClient: api);
    expect(MvpSession.userId, 'selected-user');
  });
}
