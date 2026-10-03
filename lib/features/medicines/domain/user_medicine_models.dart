/// 내 약 목록·상세 API 응답 모델.
library;

import 'display_policy.dart';

class TreatmentUse {
  final String title;
  final String description;

  const TreatmentUse({required this.title, this.description = ''});
}

enum MedicineUseType {
  eat('먹는 약', '먹는'),
  apply('바르는 약', '바르는'),
  patch('붙이는 약', '붙이는'),
  eye('눈에 넣는 약', '눈에 넣는'),
  ear('귀에 넣는 약', '귀에 넣는'),
  nose('코에 사용하는 약', '코에 사용하는'),
  inhale('들이마시는 약', '들이마시는'),
  injection('주사 약', '주사하는'),
  other('그 밖의 사용 약', '사용하는'),
  unknown('사용 방법 확인 필요', '사용하는');

  const MedicineUseType(this.label, this.action);
  final String label;
  final String action;
}

class UserMedicine {
  final String medicineCode;
  final String displayName;
  final String officialProductName;
  final String manufacturer;
  final String ingredientName;
  final String ingredientSummary;
  final String ingredientStrength;
  final String dosageForm;
  final String administrationRoute;
  final String? useRouteType;
  final String status;
  final String interactionStatus;
  final String? interactionSummary;
  final String interactionRiskLevel;
  final String interactionRiskFactor;
  final String interactionPairLabel;
  final List<String> interactionConflictNames;
  final List<Map<String, dynamic>> interactionMatches;
  final String amount;
  final String? imageUrl;
  final String? purposeLabel;
  final String? shortExplanation;
  final String? detailExplanation;
  final String? keyCaution;
  final List<String> keyCautions;
  final List<String> easyPurposes;
  final String? purposeNotice;
  final String? dosage;
  final int? frequencyPerDay;
  final List<String> administrationTimes;
  final String ingredientExplanation;
  final String ingredientHighlight;
  final String approvedUseSummary;
  final List<String> approvedUses;
  final List<String> allApprovedUses;
  final List<TreatmentUse> treatmentUses;
  final String officialUsage;
  final String officialUsageNotice;
  final List<String> askDoctorWhen;
  final List<String> possibleSideEffects;
  final String detailStatus;
  final String detailReviewStatus;
  final String detailSourceName;
  final bool detailSourceVerified;
  final String detailContentGeneratedBy;
  final String detailServedFrom;
  final int detailContentVersion;

  const UserMedicine({
    required this.medicineCode,
    required this.displayName,
    required this.officialProductName,
    this.manufacturer = '',
    required this.ingredientName,
    this.ingredientSummary = '',
    this.ingredientStrength = '',
    this.dosageForm = '',
    this.administrationRoute = '',
    this.useRouteType,
    this.status = 'active',
    this.interactionStatus = 'not_checked',
    this.interactionSummary,
    this.interactionRiskLevel = '',
    this.interactionRiskFactor = '',
    this.interactionPairLabel = '',
    this.interactionConflictNames = const [],
    this.interactionMatches = const [],
    required this.amount,
    this.imageUrl,
    this.purposeLabel,
    this.shortExplanation,
    this.detailExplanation,
    this.keyCaution,
    this.keyCautions = const [],
    this.easyPurposes = const [],
    this.purposeNotice,
    this.dosage,
    this.frequencyPerDay,
    this.administrationTimes = const [],
    this.ingredientExplanation = '',
    this.ingredientHighlight = '',
    this.approvedUseSummary = '',
    this.approvedUses = const [],
    this.allApprovedUses = const [],
    this.treatmentUses = const [],
    this.officialUsage = '',
    this.officialUsageNotice = '',
    this.askDoctorWhen = const [],
    this.possibleSideEffects = const [],
    this.detailStatus = 'PENDING',
    this.detailReviewStatus = 'UNAVAILABLE',
    this.detailSourceName = '',
    this.detailSourceVerified = false,
    this.detailContentGeneratedBy = '',
    this.detailServedFrom = '',
    this.detailContentVersion = 0,
  });

  factory UserMedicine.fromJson(Map<String, dynamic> json) {
    final rawShortExplanation = json['short_explanation']?.toString().trim();
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
      manufacturer: json['manufacturer']?.toString() ?? '',
      ingredientName:
          json['ingredient_name']?.toString() ??
          json['ingredient']?.toString() ??
          '',
      ingredientSummary: json['ingredient_summary']?.toString() ?? '',
      ingredientStrength: json['ingredient_strength']?.toString() ?? '',
      dosageForm: json['dosage_form']?.toString() ?? '',
      administrationRoute: json['administration_route']?.toString() ?? '',
      useRouteType: json['use_route_type']?.toString(),
      status: json['status']?.toString() ?? 'active',
      interactionStatus:
          json['interaction_status']?.toString() ?? 'not_checked',
      interactionSummary: json['interaction_summary']?.toString(),
      interactionRiskLevel: json['interaction_risk_level']?.toString() ?? '',
      interactionRiskFactor: json['interaction_risk_factor']?.toString() ?? '',
      interactionPairLabel: json['interaction_pair_label']?.toString() ?? '',
      interactionConflictNames: _stringList(json['interaction_conflict_names']),
      interactionMatches: [
        if (json['interaction_matches'] is List)
          for (final match in json['interaction_matches'] as List)
            if (match is Map) Map<String, dynamic>.from(match),
      ],
      amount: json['amount']?.toString() ?? '',
      imageUrl: json['image_url']?.toString(),
      purposeLabel: card.purposeLabel,
      shortExplanation: card.spoken,
      // 상세 첫 문장은 홈 목록용 짧은 분류를 재사용하지 않는다.
      // 서버가 검토된 상세 문장을 주지 않으면 이 줄 자체를 숨긴다.
      detailExplanation: (rawShortExplanation?.isNotEmpty ?? false)
          ? rawShortExplanation
          : null,
      keyCaution: json['key_caution']?.toString(),
      keyCautions: _stringList(json['key_cautions']),
      easyPurposes: _stringList(json['easy_purposes']),
      purposeNotice: json['purpose_notice']?.toString(),
      dosage: json['dosage']?.toString(),
      frequencyPerDay: _intOrNull(json['frequency_per_day']),
      administrationTimes: _stringList(json['administration_times']),
      ingredientExplanation: json['ingredient_explanation']?.toString() ?? '',
      // 서버가 숫자나 이상한 값을 주면 강조하지 않는다. 엉뚱한 곳이
      // 굵어지면 어르신은 그 말이 중요한 줄 안다.
      ingredientHighlight: json['ingredient_highlight'] is String
          ? (json['ingredient_highlight'] as String)
          : '',
      approvedUseSummary: json['approved_use_summary']?.toString() ?? '',
      approvedUses: _stringList(json['approved_uses']),
      allApprovedUses: _stringList(json['all_approved_uses']),
      treatmentUses: _treatmentUseList(json['treatment_uses']),
      officialUsage: json['official_usage']?.toString() ?? '',
      officialUsageNotice: json['official_usage_notice']?.toString() ?? '',
      askDoctorWhen: _stringList(json['ask_doctor_when']),
      possibleSideEffects: _stringList(json['possible_side_effects']),
      detailStatus: json['detail_status']?.toString() ?? 'PENDING',
      detailReviewStatus:
          json['detail_review_status']?.toString() ?? 'UNAVAILABLE',
      detailSourceName: json['detail_source_name']?.toString() ?? '',
      detailSourceVerified: json['detail_source_verified'] == true,
      detailContentGeneratedBy:
          json['detail_content_generated_by']?.toString() ?? '',
      detailServedFrom: json['detail_served_from']?.toString() ?? '',
      detailContentVersion: _intOrNull(json['detail_content_version']) ?? 0,
    );
  }

  String? get effect => homePurposeCaption(purposeLabel);

  String? get cardSpoken => cardSpokenOf(shortExplanation);

  String? get detailSpoken => detailSpokenOf(detailExplanation);

  bool get hasReviewedDetail =>
      detailReviewStatus.toUpperCase() == 'REVIEWED' &&
      (ingredientExplanation.trim().isNotEmpty ||
          approvedUseSummary.trim().isNotEmpty ||
          approvedUses.isNotEmpty ||
          allApprovedUses.isNotEmpty);

  bool get hasDetailContent =>
      ingredientExplanation.trim().isNotEmpty ||
      approvedUseSummary.trim().isNotEmpty ||
      approvedUses.isNotEmpty ||
      allApprovedUses.isNotEmpty ||
      treatmentUses.isNotEmpty;

  /// 생김새 한 줄 ("정제"). 서버가 주는 제형만 쓴다 —
  /// 색·모양은 받지 않으므로 지어내지 않는다.
  String get appearanceLine => dosageForm.trim();

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

  MedicineUseType get useType {
    // An explicit server 'unknown' must not be replaced by a client guess.
    if (useRouteType != null) {
      return MedicineUseType.values.firstWhere(
        (type) => type.name == useRouteType,
        orElse: () => MedicineUseType.unknown,
      );
    }
    // Compatibility with older servers: use explicit route/form only.
    final route = administrationRoute.trim().toLowerCase();
    const routes = {
      'apply': MedicineUseType.apply,
      '外用': MedicineUseType.apply,
      '외용': MedicineUseType.apply,
      'topical': MedicineUseType.apply,
      'patch': MedicineUseType.patch,
      'eye': MedicineUseType.eye,
      '경구': MedicineUseType.eat,
      'oral': MedicineUseType.eat,
      '흡입': MedicineUseType.inhale,
    };
    if (routes.containsKey(route)) return routes[route]!;
    final form = dosageForm;
    if (form.contains('점안') || form.contains('안연고')) return MedicineUseType.eye;
    if (form.contains('질') || form.contains('좌제')) return MedicineUseType.other;
    if (form.contains('연고') || form.contains('크림') || form.contains('로션')) {
      return MedicineUseType.apply;
    }
    if (form.contains('패치') || form.contains('패취')) {
      return MedicineUseType.patch;
    }
    if (form.contains('흡입')) return MedicineUseType.inhale;
    if (form.contains('주사')) return MedicineUseType.injection;
    if (['정제', '캡슐', '시럽', '경구액제'].contains(form)) return MedicineUseType.eat;
    return MedicineUseType.unknown;
  }

  String get doseAction => useType.action;

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

  static List<TreatmentUse> _treatmentUseList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => TreatmentUse(
            title: item['title']?.toString().trim() ?? '',
            description: item['description']?.toString().trim() ?? '',
          ),
        )
        .where((item) => item.title.isNotEmpty)
        .take(3)
        .toList();
  }

  static int? _intOrNull(dynamic raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }
}
