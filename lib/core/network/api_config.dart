import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const String _overrideBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String productionBaseUrl = 'https://alkong-yakong.onrender.com';
  // 로컬 서버가 필요할 때는 API_BASE_URL dart-define으로 명시한다.
  static const String desktopDevelopmentBaseUrl = 'http://localhost:8000';

  static String get baseUrl {
    if (_overrideBaseUrl.isNotEmpty) {
      return _overrideBaseUrl;
    }

    if (kIsWeb) {
      return kReleaseMode ? productionBaseUrl : desktopDevelopmentBaseUrl;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => productionBaseUrl,
      _ => kReleaseMode ? productionBaseUrl : desktopDevelopmentBaseUrl,
    };
  }

  static String get environmentLabel {
    if (_overrideBaseUrl.isNotEmpty) return 'override';
    return kReleaseMode ? 'production' : 'development';
  }
}
