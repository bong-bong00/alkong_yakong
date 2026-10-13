import 'dart:math';

/// One ID per measurement; reuse it if the same upload is retried.
abstract final class ClientRequestId {
  static final Random _random = Random.secure();

  static String create() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
