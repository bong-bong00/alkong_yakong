import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/theme/medicine_preserved_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medicines/domain/display_policy.dart';

/// 처방전 한 줄 — 약 이름과 며칠치.
@immutable
class PrescriptionLine {
  final String name;

  /// 며칠치인지. 서버가 안 주면 null.
  final int? days;

  const PrescriptionLine({required this.name, this.days});
}

/// 지금까지 넣은 처방전 한 장. 화면에 필요한 것만 담는다.
@immutable
class PrescriptionRecord {
  /// 받은 날. 서버가 모르면 넣은 날을 쓴다.
  final DateTime? date;

  /// 병원·약국 이름. 둘 다 없으면 비운다 — 지어내지 않는다.
  final String place;

  /// 이 처방전으로 들어온 약. 이름과 며칠치.
  final List<PrescriptionLine> medicines;

  const PrescriptionRecord({
    required this.date,
    required this.place,
    required this.medicines,
  });

  /// 이 처방전이 몇 일치인지. 약마다 다르면 가장 긴 것을 쓴다.
  /// 서버가 안 주면 null — 지어내지 않는다.
  int? get durationDays {
    final days = medicines
        .map((line) => line.days)
        .whereType<int>()
        .where((value) => value > 0);
    return days.isEmpty ? null : days.reduce((a, b) => a > b ? a : b);
  }

  factory PrescriptionRecord.fromJson(Map<String, dynamic> json) {
    String text(Object? value) => value?.toString().trim() ?? '';
    final items = json['items'];
    return PrescriptionRecord(
      date:
          DateTime.tryParse(text(json['prescribed_date'])) ??
          DateTime.tryParse(text(json['created_at'])),
      place: [
        text(json['hospital_name']),
        text(json['pharmacy_name']),
      ].where((value) => value.isNotEmpty).join(' · '),
      medicines: [
        if (items is List)
          for (final item in items)
            if (item is Map)
              PrescriptionLine(
                name: text(item['product_name']).isNotEmpty
                    ? text(item['product_name'])
                    : text(item['ocr_drug_name']),
                days: int.tryParse(text(item['duration_days'])),
              ),
      ].where((line) => line.name.isNotEmpty).toList(),
    );
  }

  /// "2026년 9월 12일". 날짜를 모르면 비운다.
  String get dateLabel {
    final at = date;
    if (at == null) return '';
    return '${at.year}년 ${at.month}월 ${at.day}일';
  }
}

/// 내가 넣은 처방전을 모아 보는 화면.
///
/// 약 목록은 "지금 먹는 약"을 보여 주지만, 여기서는 **언제 어디서 받은
/// 처방전인지**를 본다. 지난 처방도 그대로 남는다.
final prescriptionHistoryProvider = FutureProvider<List<PrescriptionRecord>>((
  ref,
) async {
  final userId = MvpSession.userId.trim();
  if (userId.isEmpty) return const [];
  final response = await ApiClient(
    baseUrl: ApiConfig.localFeatureBaseUrl,
  ).get('/api/v1/users/${Uri.encodeComponent(userId)}/prescriptions');
  if (response is! List) {
    throw const ApiException('처방전 기록을 읽을 수 없습니다.');
  }
  return [
    for (final row in response)
      if (row is Map)
        PrescriptionRecord.fromJson(Map<String, dynamic>.from(row)),
  ];
});

class PrescriptionHistoryScreen extends ConsumerWidget {
  const PrescriptionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(prescriptionHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '처방전 기록'),
          Expanded(
            child: records.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => RecoveryView(
                title: '처방전 기록을 불러오지 못했어요',
                reassurance: '인터넷이나 서버가 잠깐 끊겼을 수 있어요. ',
                reassuranceEmphasis: '고장이 아니니 걱정하지 마세요.',
                steps: const ['잠시 후 다시 눌러 보세요', '와이파이나 데이터 연결을 확인해 보세요'],
                actionLabel: '다시 불러오기',
                onAction: () => ref.invalidate(prescriptionHistoryProvider),
                stillWorksTitle: '지금도 할 수 있는 것',
                stillWorksBody: '오늘 홈에서 복약 기록과 처방전 사진 찍기는 그대로 쓸 수 있어요.',
              ),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                      child: SeniorCard(
                        radius: 26,
                        padding: const EdgeInsets.all(22),
                        child: Text(
                          '아직 넣은 처방전이 없어요.',
                          style: AppText.body(size: 19),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, index) =>
                          _RecordCard(record: list[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final PrescriptionRecord record;

  const _RecordCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (record.dateLabel.isNotEmpty)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: record.dateLabel,
                    style: AppText.cardTitle(size: 21),
                  ),
                  if (record.durationDays case final int days)
                    TextSpan(
                      text: ' · $days일치',
                      style: AppText.label(
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          if (record.place.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(record.place, style: AppText.body(size: 18)),
          ],
          if (record.medicines.isNotEmpty) ...[
            const SizedBox(height: 12),
            const SeniorDivider(),
            const SizedBox(height: 12),
            for (int i = 0; i < record.medicines.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('·', style: AppText.body(size: 19)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      // 이름에는 용량을 붙이지 않는다. 며칠치는 날짜 옆에
                      // 적고, 한 번에 몇 알인지는 약 자세히에서 본다.
                      nameWithoutStrength(record.medicines[i].name),
                      style: AppText.label(
                        size: 19,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
