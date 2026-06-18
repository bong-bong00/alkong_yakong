import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 다른 레이어에서 디오 통신을 부르기 위한 통로 (Riverpod)
final biosignalRepositoryProvider = Provider<BiosignalRepository>((ref) => BiosignalRepository());

class BiosignalRepository {
  // 백엔드 개발자(웅건님)의 FastAPI 서버 주소 (추후 Oracle Cloud IP로 변경 예정)
  final Dio _dio = Dio(BaseOptions(baseUrl: "http://localhost:8000"));

  Future<String> sendBiosignalData({
    required int hr,
    required double rmssd,
    required List<String> drugList,
  }) async {
    try {
      // 기획서 7번 항목 명세에 맞춘 POST 요청 파이프라인
      final response = await _dio.post(
        '/biosignal/analyze',
        data: {
          'hr': hr,
          'rmssd': rmssd,
          'drugs': drugList,
        },
      );

      if (response.statusCode == 200) {
        // 백엔드에서 Gemini API를 거쳐 나온 최종 자율신경계 해석 리포트 텍스트 추출
        return response.data['analysis'] ?? "해석 리포트 데이터가 비어있습니다.";
      }
      return "서버 연결에 실패했습니다. (Status Code: ${response.statusCode})";
    } on DioException catch (e) {
      return "네트워크 오류 발생: ${e.message}";
    } catch (e) {
      return "알 수 없는 오류 발생: $e";
    }
  }
}
