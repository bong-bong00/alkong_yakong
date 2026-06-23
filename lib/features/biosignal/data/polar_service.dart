import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:polar/polar.dart';

class PolarService {
  PolarService({Polar? polar}) : _polar = polar ?? Polar() {
    debugPrint('[POLAR_SERVICE] initialized');
  }

  static const String defaultDeviceId = '115F4138';

  final Polar _polar;
  final StreamController<int?> _currentBpmController =
      StreamController<int?>.broadcast();
  final StreamController<double?> _averageBpmController =
      StreamController<double?>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  final List<int> _bpmSamples = <int>[];
  final Map<String, Set<PolarSdkFeature>> _availableFeatures =
      <String, Set<PolarSdkFeature>>{};
  StreamSubscription<PolarHrData>? _hrSubscription;
  Timer? _averageTimer;
  bool _isDisposed = false;
  bool _acceptBpmEvents = false;

  Stream<int?> get currentBpmStream => _currentBpmController.stream;
  Stream<double?> get averageBpmStream => _averageBpmController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<String> get deviceDisconnectedStream =>
      _polar.deviceDisconnected.map((event) => event.info.deviceId);

  Future<String> findDeviceId({
    required String targetName,
    required String targetDeviceId,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    debugPrint(
      '[POLAR_SERVICE] search start: name=$targetName, deviceId=$targetDeviceId',
    );
    try {
      final device = await _polar
          .searchForDevice()
          .firstWhere(
            (device) =>
                device.name == targetName || device.deviceId == targetDeviceId,
          )
          .timeout(timeout);
      debugPrint(
        '[POLAR_SERVICE] device found: ${device.name} (${device.deviceId})',
      );
      return device.deviceId;
    } catch (error) {
      debugPrint('[POLAR_SERVICE] search failed: $error');
      _emitError(error);
      rethrow;
    }
  }

  Future<void> connectToDevice(String deviceId) async {
    debugPrint('[POLAR_SERVICE] connect start: $deviceId');
    final features = <PolarSdkFeature>{};
    final hrReady = Completer<void>();
    final featureSubscription = _polar.sdkFeatureReady
        .where((event) => event.identifier == deviceId)
        .listen((event) {
          features.add(event.feature);
          if (event.feature == PolarSdkFeature.hr && !hrReady.isCompleted) {
            hrReady.complete();
          }
        });
    try {
      await _polar.connectToDevice(deviceId);
      debugPrint('[POLAR_SERVICE] connected: $deviceId');
      try {
        await hrReady.future.timeout(const Duration(seconds: 10));
      } catch (error) {
        debugPrint('[POLAR_SERVICE] feature check failed: $error');
      }
      _availableFeatures[deviceId] = Set<PolarSdkFeature>.of(features);
      debugPrint('[POLAR_SERVICE] available features: $features');
      if (features.contains(PolarSdkFeature.hr)) {
        debugPrint('[POLAR_SERVICE] HR feature available');
      } else {
        debugPrint('[POLAR_SERVICE] HR feature NOT available');
      }
    } catch (error) {
      debugPrint('[POLAR_SERVICE] connect failed: $error');
      _emitError(error);
      rethrow;
    } finally {
      await featureSubscription.cancel();
    }
  }

  Future<void> disconnectFromDevice(String deviceId) async {
    await stopStreaming();
    try {
      await _polar.disconnectFromDevice(deviceId);
      _availableFeatures.remove(deviceId);
      debugPrint('[POLAR_SERVICE] disconnected');
    } catch (error) {
      _emitError(error);
      rethrow;
    }
  }

  Future<void> startHrStreaming(String deviceId) async {
    final hasHrFeature =
        _availableFeatures[deviceId]?.contains(PolarSdkFeature.hr) ?? false;
    if (!hasHrFeature) {
      const error = 'HR service not available on device';
      debugPrint('[POLAR_SERVICE] HR feature NOT available');
      _emitError(error);
      throw StateError(error);
    }
    debugPrint('[POLAR_SERVICE] HR feature available');
    await stopStreaming();
    _bpmSamples.clear();
    _acceptBpmEvents = true;
    debugPrint('[POLAR_SERVICE] hr stream start');

    _averageTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _emitAverageBpm(),
    );
    _hrSubscription = _polar
        .startHrStreaming(deviceId)
        .listen(
          (data) {
            for (final sample in data.samples) {
              final bpm = sample.hr;
              if (bpm <= 0) continue;
              if (!_acceptBpmEvents) {
                debugPrint(
                  '[POLAR_SERVICE] bpm received after stopStreaming and ignored: $bpm',
                );
                continue;
              }
              debugPrint('[POLAR_SERVICE] hr sample: $bpm');
              _bpmSamples.add(bpm);
              if (!_currentBpmController.isClosed) {
                _currentBpmController.add(bpm);
              }
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('[POLAR_SERVICE] hr stream failed: $error');
            _acceptBpmEvents = false;
            _averageTimer?.cancel();
            _averageTimer = null;
            _bpmSamples.clear();
            _emitMeasurementReset();
            _emitError(error);
          },
          onDone: () {
            debugPrint('[POLAR_SERVICE] hr stream stopped');
            _acceptBpmEvents = false;
            _averageTimer?.cancel();
            _averageTimer = null;
            _bpmSamples.clear();
            _emitMeasurementReset();
          },
          cancelOnError: false,
        );
  }

  Future<void> stopStreaming() async {
    debugPrint('[POLAR_SERVICE] stopStreaming requested');
    _acceptBpmEvents = false;
    _averageTimer?.cancel();
    _averageTimer = null;
    final subscription = _hrSubscription;
    _hrSubscription = null;
    await subscription?.cancel();
    _bpmSamples.clear();
    _emitMeasurementReset();
    debugPrint('[POLAR_SERVICE] stopStreaming completed');
  }

  void _emitMeasurementReset() {
    if (!_currentBpmController.isClosed) {
      _currentBpmController.add(null);
    }
    if (!_averageBpmController.isClosed) {
      _averageBpmController.add(null);
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    debugPrint('[POLAR_SERVICE] dispose requested');
    _isDisposed = true;
    await stopStreaming();
    await Future.wait<void>(<Future<void>>[
      _currentBpmController.close(),
      _averageBpmController.close(),
      _errorController.close(),
    ]);
    debugPrint('[POLAR_SERVICE] dispose completed');
  }

  void _emitAverageBpm() {
    if (!_acceptBpmEvents || _bpmSamples.isEmpty) return;
    final total = _bpmSamples.fold<int>(0, (sum, bpm) => sum + bpm);
    final average = total / _bpmSamples.length;
    _bpmSamples.clear();
    if (!_averageBpmController.isClosed) {
      _averageBpmController.add(average);
    }
  }

  void _emitError(Object error) {
    if (!_errorController.isClosed) {
      _errorController.add(error.toString());
    }
  }
}
