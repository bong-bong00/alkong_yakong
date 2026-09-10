import 'dart:convert';

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

  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  Future<dynamic> get(String path) async {
    try {
      final response = await _client
          .get(_uri(path), headers: _headers)
          .timeout(const Duration(seconds: 45));
      return _decodeResponse(response);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('서버에 연결할 수 없습니다: $error');
    }
  }

  Future<dynamic> post(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _client
          .post(_uri(path), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));
      return _decodeResponse(response);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('서버에 연결할 수 없습니다: $error');
    }
  }

  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${ApiConfig.baseUrl}$normalizedPath');
  }

  dynamic _decodeResponse(http.Response response) {
    dynamic data;
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw ApiException(
          '서버 응답이 올바른 JSON 형식이 아닙니다.',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    final detail = data is Map<String, dynamic> ? data['detail'] : null;
    throw ApiException(
      detail?.toString() ?? 'API 요청에 실패했습니다. (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json; charset=UTF-8',
  };
}
