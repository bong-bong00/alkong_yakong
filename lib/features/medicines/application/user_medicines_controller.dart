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
    final data = Map<String, dynamic>.from(med);
    final explanation = response['explanation'];
    if (explanation is Map) {
      data['short_explanation'] =
          explanation['short_explanation'] ?? data['short_explanation'];
      data['ingredient_explanation'] = explanation['ingredient_explanation'];
      data['approved_use_summary'] = explanation['approved_use_summary'];
      data['approved_uses'] = explanation['approved_uses'];
      data['all_approved_uses'] = explanation['all_approved_uses'];
      data['detail_review_status'] = explanation['review_status'];
      data['detail_status'] = explanation['status'];
    }
    final patientDosage = response['patient_dosage'];
    if (patientDosage is Map) {
      data['amount'] = patientDosage['amount'] ?? data['amount'];
      data['dosage'] = patientDosage['dosage'] ?? data['dosage'];
      data['frequency_per_day'] =
          patientDosage['frequency_per_day'] ?? data['frequency_per_day'];
      data['administration_times'] =
          patientDosage['administration_times'] ?? data['administration_times'];
    }
    final officialUsage = response['official_usage'];
    if (officialUsage is Map) {
      data['official_usage'] = officialUsage['text'];
      data['official_usage_notice'] = officialUsage['notice'];
    }
    final safety = response['safety'];
    if (safety is Map) {
      data['key_cautions'] = safety['key_cautions'] ?? data['key_cautions'];
      data['ask_doctor_when'] = safety['ask_doctor_when'];
      data['possible_side_effects'] = safety['possible_side_effects'];
      data['interaction_status'] =
          safety['interaction_status'] ?? data['interaction_status'];
      data['interaction_summary'] =
          safety['interaction_summary'] ?? data['interaction_summary'];
      data['interaction_risk_level'] =
          safety['interaction_risk_level'] ?? data['interaction_risk_level'];
      data['interaction_conflict_names'] =
          safety['interaction_conflict_names'] ??
          data['interaction_conflict_names'];
      data['interaction_risk_factor'] =
          safety['interaction_risk_factor'] ?? data['interaction_risk_factor'];
      data['interaction_pair_label'] =
          safety['interaction_pair_label'] ?? data['interaction_pair_label'];
    }
    final source = response['source'];
    if (source is Map) {
      data['detail_source_name'] = source['name'];
      data['detail_source_verified'] = source['source_verified'];
      data['detail_content_generated_by'] = source['content_generated_by'];
      data['detail_served_from'] = source['served_from'];
      data['detail_content_version'] = source['content_version'];
    }
    return UserMedicine.fromJson(data);
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
