import 'package:alkong_yakong/core/network/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('메인 주소를 유지하고 약 기능만 본인 작업공간 서버로 연결한다', () {
    expect(ApiConfig.productionBaseUrl, 'https://alkong-yakong.onrender.com');
    expect(
      ApiConfig.medicationFeatureBaseUrl,
      'https://alkong-yakong-medication.onrender.com',
    );
  });
}
