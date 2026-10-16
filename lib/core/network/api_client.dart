import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import '../session/session_credentials.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {
  final http.Client _client;
  final String _baseUrl;
  static bool _didLogEnvironment = false;
  static const Duration _defaultTimeout = Duration(seconds: 45);

  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceAll(RegExp(r'/$'), '') {
    if (kDebugMode && !_didLogEnvironment) {
      _didLogEnvironment = true;
      debugPrint(
        '[API] environment=${ApiConfig.environmentLabel} '
        'baseUrl=$_baseUrl',
      );
    }
  }

  Future<dynamic> get(String path, {bool allowCache = true}) async {
    final generation = SessionCredentials.generation;
    try {
      final data = await _send(
        () => _client.get(_uri(path), headers: _headersFor(path)),
      );
      await SessionCredentials.cacheRead(_baseUrl, path, data, generation);
      SessionCredentials.markAvailable(_baseUrl, path);
      return data;
    } on ApiException catch (error) {
      if (error.statusCode == null ||
          const [502, 503, 504].contains(error.statusCode)) {
        SessionCredentials.markUnavailable(_baseUrl, path);
        final cached = await SessionCredentials.cachedRead(
          _baseUrl,
          path,
          generation,
        );
        if (allowCache && cached != null) return cached;
      }
      rethrow;
    }
  }

  Future<dynamic> post(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = _defaultTimeout,
    Map<String, String> headers = const {},
  }) => _send(
    () => _client.post(
      _uri(path),
      headers: {..._headersFor(path), ...headers},
      body: jsonEncode(body),
    ),
    timeout: timeout,
  );

  Future<dynamic> patch(String path, {required Map<String, dynamic> body}) =>
      _send(
        () => _client.patch(
          _uri(path),
          headers: _headersFor(path),
          body: jsonEncode(body),
        ),
      );

  Future<dynamic> delete(String path) =>
      _send(() => _client.delete(_uri(path), headers: _headersFor(path)));

  Future<dynamic> _send(
    Future<http.Response> Function() request, {
    Duration timeout = _defaultTimeout,
  }) async {
    final generation = SessionCredentials.generation;
    final hadCredential = SessionCredentials.isValid;
    try {
      final response = await request().timeout(timeout);
      if (hadCredential && generation != SessionCredentials.generation) {
        throw const ApiException('사용자가 바뀌었어요. 다시 확인해 주세요.');
      }
      if (response.statusCode == 401 && hadCredential) {
        await SessionCredentials.clear();
      }
      return _decodeResponse(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      if (SessionCredentials.isValid) SessionCredentials.offline.value = true;
      // 무료 서버는 아무도 안 쓰면 잠든다. 처음 깨우는 데 30초 넘게
      // 걸리기도 한다. 고장이 아니라 기다리면 되는 일이라고 말한다.
      throw const ApiException('서버를 깨우는 중이에요. 잠시 뒤 다시 해 주세요.');
    } catch (error) {
      if (SessionCredentials.isValid) SessionCredentials.offline.value = true;
      throw const ApiException('서버에 연결할 수 없어요. 잠시 뒤 다시 시도해 주세요.');
    }
  }

  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalizedPath');
  }

  dynamic _decodeResponse(http.Response response) {
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final isJsonContentType =
        contentType.contains('application/json') ||
        contentType.contains('+json');
    dynamic data;
    if (response.body.isNotEmpty) {
      if (!isSuccess && !isJsonContentType) {
        throw ApiException(
          'API 요청에 실패했습니다. (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        if (!isSuccess) {
          throw ApiException(
            'API 요청에 실패했습니다. (HTTP ${response.statusCode})',
            statusCode: response.statusCode,
          );
        }
        throw ApiException(
          '서버 응답이 올바른 JSON 형식이 아닙니다.',
          statusCode: response.statusCode,
        );
      }
    }

    if (isSuccess) {
      return data;
    }

    final detail = data is Map<String, dynamic> ? data['detail'] : null;
    var message = 'API 요청에 실패했습니다. (HTTP ${response.statusCode})';
    if (detail is Map) {
      message =
          detail['message']?.toString() ??
          detail['error']?.toString() ??
          detail.toString();
    } else if (detail != null) {
      message = detail.toString();
    }
    throw ApiException(message, statusCode: response.statusCode);
  }

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json; charset=UTF-8',
  };

  Map<String, String> _headersFor(String path) {
    final token = SessionCredentials.accessToken;
    final publicLogin =
        path == '/api/v1/users/login' || path == '/api/v1/users';
    final origin = Uri.parse(_baseUrl).origin;
    final trusted = {
      Uri.parse(ApiConfig.baseUrl).origin,
      Uri.parse(ApiConfig.localFeatureBaseUrl).origin,
    }.contains(origin);
    return {
      ..._headers,
      if (token != null && trusted && !publicLogin)
        'Authorization': 'Bearer $token',
    };
  }
}
