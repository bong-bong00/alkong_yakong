import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

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

  Future<dynamic> get(String path) =>
      _send(() => _client.get(_uri(path), headers: _headers));

  Future<dynamic> post(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = _defaultTimeout,
    Map<String, String> headers = const {},
  }) => _send(
    () => _client.post(
      _uri(path),
      headers: {..._headers, ...headers},
      body: jsonEncode(body),
    ),
    timeout: timeout,
  );

  Future<dynamic> patch(String path, {required Map<String, dynamic> body}) =>
      _send(
        () => _client.patch(
          _uri(path),
          headers: _headers,
          body: jsonEncode(body),
        ),
      );

  Future<dynamic> delete(String path) =>
      _send(() => _client.delete(_uri(path), headers: _headers));

  Future<dynamic> _send(
    Future<http.Response> Function() request, {
    Duration timeout = _defaultTimeout,
  }) async {
    try {
      final response = await request().timeout(timeout);
      return _decodeResponse(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      // 무료 서버는 아무도 안 쓰면 잠든다. 처음 깨우는 데 30초 넘게
      // 걸리기도 한다. 고장이 아니라 기다리면 되는 일이라고 말한다.
      throw const ApiException('서버를 깨우는 중이에요. 잠시 뒤 다시 해 주세요.');
    } catch (error) {
      throw ApiException('서버에 연결할 수 없습니다: $error');
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
}
