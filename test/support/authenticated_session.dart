import 'dart:convert';

import 'package:alkong_yakong/core/session/auth_session.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/session/session_credentials.dart';

Map<String, dynamic> loginResponse(
  String id, {
  String role = 'patient',
  Duration lifetime = const Duration(hours: 1),
}) {
  final claims = {
    'sub': id,
    'role': role,
    'kind': 'access',
    'aud': 'alkong-yakong',
    'exp': DateTime.now().add(lifetime).millisecondsSinceEpoch ~/ 1000,
  };
  final encoded = base64Url
      .encode(utf8.encode(jsonEncode(claims)))
      .replaceAll('=', '');
  return {
    'id': id,
    'name': '검증용 사용자',
    'role': role,
    'phone': '01012345678',
    'is_pregnant': false,
    'access_token': '$encoded.test-signature',
  };
}

Future<void> authenticatedSession(String id, {String role = 'patient'}) async {
  await SessionCredentials.install(loginResponse(id, role: role));
  MvpSession.userId = id;
  await AuthSession.setLoggedIn(role);
}
