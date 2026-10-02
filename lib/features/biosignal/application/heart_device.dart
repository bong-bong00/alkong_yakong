import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 심박 기기를 쓰고 계신지.
///
/// 홈은 이 값만 보고 흐름을 고른다 — 기기가 있으면 "먹기 전에 재고 → 먹고 →
/// 먹은 뒤에 또 재는" 세 걸음으로, 없으면 "먹었어요" 하나로 간다.
///
/// 블루투스로 지금 붙어 있는지를 홈에서 직접 확인하지는 않는다. 확인하려면
/// 화면을 열 때마다 기기를 찾아야 해서 몇 초씩 걸리고, 그동안 홈이 어느
/// 흐름인지 못 정한다. 한 번 연결해 쓰신 적이 있으면 "쓰는 분"으로 보고,
/// 연결을 끊으시면 그때 내린다.
class HeartDeviceController extends Notifier<bool> {
  static const _key = 'heart.paired';

  @override
  bool build() {
    unawaited(_load());
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? false;
    } catch (_) {
      // 저장소를 못 열면 기기가 없는 쪽으로 둔다. 없는데 있다고 하면
      // 심박수를 재라고 시키고는 아무 일도 일어나지 않는다.
    }
  }

  Future<void> set(bool paired) async {
    if (state == paired) return;
    state = paired;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, paired);
    } catch (_) {
      // 화면에는 이미 반영됐다. 다음 실행 때 되돌아갈 뿐이다.
    }
  }
}

final heartDevicePairedProvider =
    NotifierProvider<HeartDeviceController, bool>(HeartDeviceController.new);
