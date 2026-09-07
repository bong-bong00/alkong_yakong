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
      // 실제 기기: PC의 현재 LAN IP (ipconfig의 IPv4). IP가 바뀌면 여기도 바꿀 것.
      // 안드로이드 에뮬레이터만 쓸 때는 아래를 http://10.0.2.2:8000 으로.
      TargetPlatform.android => 'http://172.16.42.25:8000',
      _ => 'http://localhost:8000',
    };
  }
}
