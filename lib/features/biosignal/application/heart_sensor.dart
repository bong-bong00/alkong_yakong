import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/network/api_client.dart';
import '../../../core/session/mvp_session.dart';
import '../data/biosignal_dataset_collector.dart';
import '../data/polar_service.dart';

/// 센서가 지금 어떤 상태인지.
///
/// 화면은 이 다섯 가지만 보고 그린다. 붙는 중인지 끊긴 것인지를
/// 화면마다 따로 판단하면 같은 상황을 서로 다르게 말하게 된다.
enum HeartSensorStatus { idle, connecting, streaming, disconnected, failed }

/// 폴라 센서 한 대와 잇는 일을 모아 둔 자리.
///
/// **화면은 상태만 읽는다.** 연결·구독·업로드는 전부 여기서만 일어난다.
/// 화면마다 배선을 따로 두면 한쪽만 고쳐지고 다른 쪽이 남는다.
///
/// 두 갈래를 섞지 않는다.
/// - 운영: 30초 평균을 `/api/v1/biosignal/heart-rate` 로 올린다.
/// - 데이터셋: 매 초 값을 [BiosignalDatasetCollector] 로 따로 모은다.
class HeartSensor extends ChangeNotifier {
  HeartSensor({
    PolarService? polar,
    ApiClient? apiClient,
    BiosignalDatasetCollector? datasetCollector,
  })  : _polar = polar ?? PolarService(),
        _apiClient = apiClient ?? ApiClient(),
        _datasetCollector = datasetCollector ?? BiosignalDatasetCollector();

  /// 정상으로 보는 범위. 이 밖이면 화면이 확인을 권한다.
  static const int normalLow = 50;
  static const int normalHigh = 110;

  /// 최근 값 몇 개까지 들고 있을지. 가장 낮게·가장 높게를 여기서 낸다.
  static const int _sampleWindow = 60;

  final PolarService _polar;
  final ApiClient _apiClient;
  final BiosignalDatasetCollector _datasetCollector;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<int> _samples = <int>[];

  HeartSensorStatus _status = HeartSensorStatus.idle;
  int? _bpm;
  String? _deviceId;
  DateTime? _lastReadAt;
  bool _disposed = false;

  HeartSensorStatus get status => _status;
  int? get bpm => _bpm;
  String? get deviceId => _deviceId;
  DateTime? get lastReadAt => _lastReadAt;

  /// 잰 값들. 새 화면의 "가장 낮게 / 가장 높게"가 이걸 쓴다.
  List<int> get samples => List.unmodifiable(_samples);

  int? get lowest => _samples.isEmpty ? null : _samples.reduce((a, b) => a < b ? a : b);
  int? get highest => _samples.isEmpty ? null : _samples.reduce((a, b) => a > b ? a : b);

  /// 아직 한 번도 못 잰 동안은 "이상하다"고 말하지 않는다.
  bool get normal {
    final bpm = _bpm;
    return bpm == null || (bpm >= normalLow && bpm <= normalHigh);
  }

  void _set(HeartSensorStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

  /// 센서를 찾아 붙고 심박 스트림을 연다.
  Future<void> start() async {
    if (_disposed) return;
    _set(HeartSensorStatus.connecting);

    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final deviceId = await _polar.findDeviceId(
        targetName: 'Polar Verity Sense',
        targetDeviceId: PolarService.defaultDeviceId,
      );
      await _polar.connectToDevice(deviceId);
      await _polar.startHrStreaming(deviceId);

      if (_disposed) return;
      _deviceId = deviceId;
      _set(HeartSensorStatus.streaming);

      _subscriptions.add(
        _polar.currentBpmStream.listen((bpm) {
          if (_disposed || bpm == null) return;
          // 데이터셋은 운영 기록과 따로 모은다.
          _datasetCollector.addPolarBpm(
            bpm,
            deviceId: _deviceId ?? PolarService.defaultDeviceId,
          );
          _bpm = bpm;
          _lastReadAt = DateTime.now();
          _samples.add(bpm);
          if (_samples.length > _sampleWindow) _samples.removeAt(0);
          notifyListeners();
        }),
      );
      _subscriptions.add(
        _polar.averageBpmStream.listen((average) {
          if (average != null) unawaited(_sendAverageBpm(average));
        }),
      );
      _subscriptions.add(
        _polar.deviceDisconnectedStream.listen((_) {
          _set(HeartSensorStatus.disconnected);
        }),
      );
      _subscriptions.add(
        _polar.errorStream.listen((_) {
          _set(HeartSensorStatus.failed);
        }),
      );
    } catch (_) {
      _set(HeartSensorStatus.failed);
    }
  }

  /// 30초 평균만 서버로 올린다. 매 초 값을 올리면 기록이 잡음이 된다.
  Future<void> _sendAverageBpm(double average) async {
    final userId = MvpSession.userId.trim();
    if (userId.isEmpty) {
      debugPrint('Skipping average BPM upload: user ID is empty.');
      return;
    }
    try {
      await _apiClient.post(
        '/api/v1/biosignal/heart-rate',
        body: {
          'user_id': userId,
          'bpm': average.round(),
          'device_id': _deviceId ?? PolarService.defaultDeviceId,
          'source': 'POLAR_30S_AVERAGE',
        },
      );
      debugPrint('[POLAR_UI] avg upload success');
    } on ApiException catch (error) {
      debugPrint('[POLAR_UI] avg upload failed: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    unawaited(_polar.stopStreaming());
    final deviceId = _deviceId;
    if (deviceId != null) {
      unawaited(_polar.disconnectFromDevice(deviceId));
    }
    unawaited(_polar.dispose());
    super.dispose();
  }
}
