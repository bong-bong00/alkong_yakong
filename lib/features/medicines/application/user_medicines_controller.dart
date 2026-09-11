import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/session/mvp_session.dart';
import '../domain/display_policy.dart';
import '../domain/user_medicine_models.dart';

final userMedicinesProvider =
    AsyncNotifierProvider<UserMedicinesController, List<UserMedicine>>(
      UserMedicinesController.new,
    );

/// 활성 내 약 목록·상세를 서버에서 불러온다.
class UserMedicinesController extends AsyncNotifier<List<UserMedicine>> {
  final _api = ApiClient();

  @override
  Future<List<UserMedicine>> build() async {
    return _loadMedicines();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_loadMedicines);
  }

  Future<UserMedicine> loadDetail(String medicineCode) async {
    final code = medicineCode.trim();
    if (code.isEmpty) {
      throw const ApiException('약 코드가 없습니다.');
    }
    final userId = Uri.encodeComponent(MvpSession.userId);
    final response = await _api.get(
      '/api/v1/users/$userId/medicines/${Uri.encodeComponent(code)}',
    );
    if (response is! Map) {
      throw const ApiException('약 정보를 읽을 수 없습니다.');
    }
    final med = response['medicine'];
    if (med is! Map) {
      throw const ApiException('약 정보를 읽을 수 없습니다.');
    }
    return UserMedicine.fromJson(Map<String, dynamic>.from(med));
  }

  Future<List<UserMedicine>> _loadMedicines() async {
    final userId = Uri.encodeComponent(MvpSession.userId);
    final response = await _api.get('/api/v1/users/$userId/medicines');
    if (response is! Map) return const [];
    final raw = response['medicines'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) UserMedicine.fromJson(Map<String, dynamic>.from(item)),
    ].where((med) => !isMockDrugInfoName(med.displayName)).toList();
  }
}
