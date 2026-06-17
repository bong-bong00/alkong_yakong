import 'package:polar/polar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 다른 팀원들이 ref.read(polarServiceProvider)로 접근할 수 있게 전역 선언
final polarServiceProvider = Provider<PolarService>((ref) => PolarService());

class PolarService {
  final polar = Polar();

  // 1. 앱 시작 시 권한을 요청하는 함수
  Future<void> requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  // 2. 센서와 연결하는 함수 (팀원이 버튼에 연결할 함수)
  Future<void> connectToSensor(String deviceId) async {
    // deviceId는 센서 뒷면에 적힌 영문/숫자 (예: "1A2B3C4D")
    await polar.connectToDevice(deviceId);
  }

  // 3. 센서 연결을 끊는 함수
  Future<void> disconnectSensor(String deviceId) async {
    await polar.disconnectFromDevice(deviceId);
  }

  // 4. 심박수 데이터를 뱉어내는 파이프 (팀원이 UI에 뿌릴 데이터)
  Stream<int> get heartRateStream {
    return polar.heartRateStream.map((event) => event.data.hr);
  }

  // 5. PPI(심박변이도 원시 데이터)를 뱉어내는 파이프
  Stream<int> get ppiStream {
    return polar.ppiStream.map((event) {
      // PPI 데이터 중 첫 번째 샘플의 간격(ms)을 추출
      if (event.data.samples.isNotEmpty) {
        return event.data.samples.first.ppi;
      }
      return 0;
    });
  }

  // 6. 가속도(3축) 데이터를 뱉어내는 파이프 (움직임 감지용)
  Stream<PolarAccData> get accStream {
    return polar.accStream;
  }
}
}
