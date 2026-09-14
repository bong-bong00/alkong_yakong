import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const String _overrideBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String productionBaseUrl = 'https://alkong-yakong.onrender.com';
  // 실제 안드로이드 기기에서 같은 로컬 네트워크의 개발 서버로 연결한다.
  // 에뮬레이터에서는 필요할 때
  // --dart-define=API_BASE_URL=http://10.0.2.2:8000 을 사용한다.
  static const String androidDevelopmentBaseUrl = 'http://172.16.42.25:8000';
  static const String desktopDevelopmentBaseUrl = 'http://localhost:8000';

  static String get baseUrl {
    if (_overrideBaseUrl.isNotEmpty) {
      return _overrideBaseUrl;
    }

    if (kIsWeb) {
      return kReleaseMode ? productionBaseUrl : desktopDevelopmentBaseUrl;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        kReleaseMode ? productionBaseUrl : androidDevelopmentBaseUrl,
      _ => kReleaseMode ? productionBaseUrl : desktopDevelopmentBaseUrl,
    };
  }

  static String get environmentLabel {
    if (_overrideBaseUrl.isNotEmpty) return 'override';
    return kReleaseMode ? 'production' : 'development';
  }
}
