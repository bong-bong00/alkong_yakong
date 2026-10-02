import 'package:alkong_yakong/core/network/api_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android uses Render unless API_BASE_URL is explicitly overridden', () {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      const override = String.fromEnvironment('API_BASE_URL');
      expect(
        ApiConfig.baseUrl,
        override.isEmpty ? ApiConfig.productionBaseUrl : override,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
