import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';

/// Compare actual prescription IDs, not previously seen medicine codes.
/// The baseline survives leaving this screen or restarting the app.
class FamilyPrescriptionRepository {
  FamilyPrescriptionRepository({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient(baseUrl: ApiConfig.localFeatureBaseUrl);

  final ApiClient _api;
  String _key(String userId) => 'family_prescription_baseline_$userId';

  Future<List<Map<String, dynamic>>> _load(String userId) async {
    final response = await _api.get(
      '/api/v1/users/${Uri.encodeComponent(userId)}/prescriptions',
    );
    if (response is! List ||
        response.any((row) => row is! Map || row['id'] == null)) {
      throw const ApiException('처방전 등록 여부를 확인하지 못했어요.');
    }
    return response
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> begin(String userId) async {
    final records = await _load(userId);
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _key(userId),
      jsonEncode(records.map((row) => row['id'].toString()).toList()),
    );
    if (!saved) throw const ApiException('부탁한 내용을 저장하지 못했어요.');
  }

  Future<bool> isPending(String userId) async =>
      (await SharedPreferences.getInstance()).containsKey(_key(userId));

  Future<List<Map<String, dynamic>>> arrivals(String userId) async {
    final raw = (await SharedPreferences.getInstance()).getString(_key(userId));
    if (raw == null) {
      throw const ApiException('가족에게 부탁하기를 다시 눌러 주세요.');
    }
    final baseline = (jsonDecode(raw) as List)
        .map((id) => id.toString())
        .toSet();
    return (await _load(
      userId,
    )).where((row) => !baseline.contains(row['id'].toString())).toList();
  }

  Future<void> finish(String userId) async {
    await (await SharedPreferences.getInstance()).remove(_key(userId));
  }
}
