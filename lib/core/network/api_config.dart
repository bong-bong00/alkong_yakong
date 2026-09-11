import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const String _overrideBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String productionBaseUrl = 'https://alkong-yakong.onrender.com';
  static const String androidDevelopmentBaseUrl = 'http://10.0.2.2:8000';
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
