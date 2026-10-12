import 'package:flutter/foundation.dart';

abstract final class OfflineStatus {
  static final active = ValueNotifier<bool>(false);
  static final _paths = <String>{};
  static void cached(String path) {
    _paths.add(path);
    active.value = true;
  }

  static void fresh(String path) {
    _paths.remove(path);
    active.value = _paths.isNotEmpty;
  }

  static void clear() {
    _paths.clear();
    active.value = false;
  }
}
