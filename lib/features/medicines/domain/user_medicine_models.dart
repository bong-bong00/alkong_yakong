/// 내 약 목록·상세 API 응답 모델.
library;

import 'display_policy.dart';

class UserMedicine {
  final String medicineCode;
  final String displayName;
  final String officialProductName;
  final String ingredientName;
  final String ingredientSummary;
  final String ingredientStrength;
  final String dosageForm;
  final String administrationRoute;
  final String status;
  final String interactionStatus;
  final String? interactionSummary;
  final String interactionRiskLevel;
  final List<String> interactionConflictNames;
  final String amount;
  final String? purposeLabel;
  final String? shortExplanation;
  final String? keyCaution;
  final List<String> keyCautions;
  final List<String> easyPurposes;
  final String? purposeNotice;
  final String? dosage;
  final int? frequencyPerDay;
  final List<String> administrationTimes;

  const UserMedicine({
    required this.medicineCode,
    required this.displayName,
    required this.officialProductName,
    required this.ingredientName,
    this.ingredientSummary = '',
    this.ingredientStrength = '',
    this.dosageForm = '',
    this.administrationRoute = '',
    this.status = 'active',
    this.interactionStatus = 'not_checked',
    this.interactionSummary,
    this.interactionRiskLevel = '',
    this.interactionConflictNames = const [],
    required this.amount,
    this.purposeLabel,
    this.shortExplanation,
    this.keyCaution,
    this.keyCautions = const [],
    this.easyPurposes = const [],
    this.purposeNotice,
    this.dosage,
    this.frequencyPerDay,
    this.administrationTimes = const [],
  });

  factory UserMedicine.fromJson(Map<String, dynamic> json) {
    final card = resolveMyMedicineCard(
      medicineCode: json['medicine_code']?.toString(),
      productName: json['product_name']?.toString(),
      displayName: json['display_name']?.toString(),
      ingredient: json['ingredient']?.toString(),
      purposeLabel: json['purpose_label']?.toString(),
      shortExplanation: json['short_explanation']?.toString(),
      easyCategory: json['easy_category']?.toString(),
    );
    return UserMedicine(
      medicineCode: json['medicine_code']?.toString() ?? '',
      displayName: card.name,
      officialProductName:
          json['official_product_name']?.toString() ?? card.name,
      ingredientName:
          json['ingredient_name']?.toString() ??
          json['ingredient']?.toString() ??
          '',
      ingredientSummary: json['ingredient_summary']?.toString() ?? '',
      ingredientStrength: json['ingredient_strength']?.toString() ?? '',
      dosageForm: json['dosage_form']?.toString() ?? '',
      administrationRoute: json['administration_route']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      interactionStatus:
          json['interaction_status']?.toString() ?? 'not_checked',
      interactionSummary: json['interaction_summary']?.toString(),
      interactionRiskLevel: json['interaction_risk_level']?.toString() ?? '',
      interactionConflictNames: _stringList(json['interaction_conflict_names']),
      amount: json['amount']?.toString() ?? '',
      purposeLabel: card.purposeLabel,
      shortExplanation: card.spoken,
      keyCaution: json['key_caution']?.toString(),
      keyCautions: _stringList(json['key_cautions']),
      easyPurposes: _stringList(json['easy_purposes']),
      purposeNotice: json['purpose_notice']?.toString(),
      dosage: json['dosage']?.toString(),
      frequencyPerDay: _intOrNull(json['frequency_per_day']),
      administrationTimes: _stringList(json['administration_times']),
    );
  }

  String? get effect => cardPurposeLabel(purposeLabel);

  String? get cardSpoken => cardSpokenOf(shortExplanation);

  String get ingredientLabel {
    final summary = ingredientSummary.trim().isNotEmpty
        ? ingredientSummary.trim()
        : compactIngredientSummary(ingredientName);
    return [
      summary,
      ingredientStrength.trim(),
    ].where((value) => value.isNotEmpty).join(' · ');
  }

  String get frequencyLabel {
    final freq = frequencyPerDay;
    if (freq == null || freq <= 0) return '복용 횟수 정보 없음';
    return '하루 $freq번';
  }

  String get dosageLabel {
    final take = amount.trim();
    if (take.isNotEmpty) return take;
    final raw = dosage?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return '용량 정보 없음';
  }

  String get doseAction {
    final value = '$dosageForm $administrationRoute';
    if (value.contains('점안')) return '눈에 넣는';
    if (value.contains('연고') || value.contains('크림') || value.contains('외용')) {
      return '바르는';
    }
    if (value.contains('패치') || value.contains('패취')) return '붙이는';
    if (value.contains('흡입')) return '들이마시는';
    return '먹는';
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((value) {
          if (value is Map) {
            return value['easy_label']?.toString() ??
                value['short_sentence']?.toString() ??
                '';
          }
          return value.toString();
        })
        .where((value) => value.trim().isNotEmpty)
        .toList();
  }

  static int? _intOrNull(dynamic raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }
}
