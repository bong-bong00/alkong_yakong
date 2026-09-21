import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const String _overrideBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _overrideLocalBaseUrl = String.fromEnvironment(
    'LOCAL_API_BASE_URL',
  );
  static const String productionBaseUrl = 'https://alkong-yakong.onrender.com';
  // 개발 중인 OCR·OCR 결과 등록·약 상세만 같은 네트워크의 로컬 FastAPI로 보낸다.
  // 로그인과 기본 목록 등 나머지 요청은 baseUrl(Render)을 계속 사용한다.
  static const String localBackendBaseUrl = 'http://172.16.42.25:8000';
  static const String desktopDevelopmentBaseUrl = 'http://localhost:8000';

  static String get localFeatureBaseUrl => _overrideLocalBaseUrl.isNotEmpty
      ? _overrideLocalBaseUrl
      : localBackendBaseUrl;

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
