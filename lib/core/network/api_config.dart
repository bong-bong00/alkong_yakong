import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const String _overrideBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_overrideBaseUrl.isNotEmpty) {
      return _overrideBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:8000';
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'http://172.16.42.121:8000',
      _ => 'http://localhost:8000',
    };
  }
}
