import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../dashboard/presentation/screens/patient_data.dart';
import '../../../medicines/application/user_medicines_controller.dart';
import '../../../medicines/domain/user_medicine_models.dart';
import '../../../profile/domain/user_profile.dart';
import '../../../medicines/domain/display_policy.dart';

String? illnessHistoryLabel(List<String> illnesses, bool? legacyFlag) {
  if (illnesses.isNotEmpty) return illnesses.join(', ');
  return switch (legacyFlag) {
    true => '있으세요',
    false => '없어요',
    null => null,
  };
}

/// 그 어르신의 몸 이야기를 가져온다. 못 가져오면 null.
final carePatientProfileProvider = FutureProvider.family<UserProfile?, String>((
  ref,
  patientId,
) async {
  if (patientId.trim().isEmpty) return null;
  final response = await ApiClient().get(
    '/api/v1/users/${Uri.encodeComponent(patientId)}',
  );
  if (response is! Map) throw const ApiException('건강정보를 불러오지 못했어요.');
  return UserProfile.fromJson(Map<String, dynamic>.from(response));
});

/// 보호자 · 어르신 한 분 (프로토타입 91 · 92).
///
/// 대신 처방전을 넣을 때 조심할 것을 맨 위에 둔다.
class CarePatientScreen extends ConsumerWidget {
  final CarePatient patient;

  const CarePatientScreen({super.key, required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(
      carePatientProfileProvider(patient.patientId),
    );
    final profile = profileState.valueOrNull;
    final allergies = profile?.allergies ?? const <String>[];
    final medicines = ref.watch(patientMedicinesProvider(patient.patientId));
    final diseases = profile?.diseases ?? const <String>[];
    final missingProfileLabel = profile == null
        ? (profileState.isLoading ? '불러오는 중이에요' : '정보를 확인하지 못했어요')
        : '미입력';

    String? sizeLine() {
      final height = profile?.heightCm;
      final weight = profile?.weightKg;
      if (height == null && weight == null) return null;
      return [
        if (height != null) '${height.toStringAsFixed(0)}cm',
        if (weight != null) '${weight.toStringAsFixed(0)}kg',
      ].join(' · ');
    }

    String? birthLine() {
      final birth = profile?.birthDate;
      if (birth == null) return null;
      return '${birth.year}년 ${birth.month}월 ${birth.day}일';
    }

    String? habitLine() {
      final smoking = profile?.smoking;
      final drinking = profile?.drinking;
      if (smoking == null && drinking == null) return null;
      return [
        if (smoking != null) '담배 ${lifestyleLabel(smoking)}',
        if (drinking != null) '술 $drinking',
      ].join(' · ');
    }

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          SeniorBackHeader(title: '${patient.title} 님', alignStart: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (profileState.hasError) ...[
                    SeniorCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '건강정보를 불러오지 못했어요',
                            style: AppText.cardTitle(size: 20),
                          ),
                          const SizedBox(height: 8),
                          SeniorButton(
                            label: '다시 불러오기',
                            kind: SeniorButtonKind.secondary,
                            fontSize: 18,
                            minHeight: 52,
                            onPressed: () => ref.invalidate(
                              carePatientProfileProvider(patient.patientId),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (allergies.isNotEmpty) ...[
                    _WarnCard(text: '${allergies.join(' · ')} 알레르기가 있어요'),
                    const SizedBox(height: 12),
                  ],
                  _MedicineListCard(medicines: medicines),
                  const SizedBox(height: 12),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        Text('기본 정보', style: AppText.cardTitle(size: 21)),
                        _FactRow(
                          label: '연세',
                          value: patient.age == null ? null : '${patient.age}세',
                        ),
                        const SeniorDivider(),
                        _FactRow(
                          label: '생년월일',
                          value: birthLine(),
                          missingLabel: missingProfileLabel,
                        ),
                        const SeniorDivider(),
                        _FactRow(
                          label: '성별',
                          missingLabel: missingProfileLabel,
                          value: switch (profile?.gender) {
                            'M' => '남자',
                            'F' => '여자',
                            _ => null,
                          },
                        ),
                        const SeniorDivider(),
                        _FactRow(
                          label: '키 · 몸무게',
                          value: sizeLine(),
                          missingLabel: missingProfileLabel,
                        ),
                        const SeniorDivider(),
                        _FactRow(
                          label: '혈액형',
                          value: profile?.bloodType,
                          missingLabel: missingProfileLabel,
                        ),
                        const SeniorDivider(),
                        _FactRow(label: '연락처', value: patient.phone),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('지금 앓고 있는 병', style: AppText.label(size: 18)),
                        const SizedBox(height: 12),
                        if (diseases.isEmpty)
                          Text(
                            profile == null
                                ? missingProfileLabel
                                : '등록된 질환이 없어요',
                            style: AppText.body(size: 18),
                          )
                        else
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final disease in diseases)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.pointTint,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    disease,
                                    style: AppText.cardTitle(
                                      size: 19,
                                      color: AppColors.point,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        Text('병력 · 생활습관', style: AppText.cardTitle(size: 21)),
                        _FactRow(
                          label: '과거에 앓았던 병',
                          missingLabel: missingProfileLabel,
                          value: illnessHistoryLabel(
                            profile?.pastIllnesses ?? const [],
                            profile?.pastHistory,
                          ),
                        ),
                        const SeniorDivider(),
                        _FactRow(
                          label: '가족 병력',
                          missingLabel: missingProfileLabel,
                          value: illnessHistoryLabel(
                            profile?.familyIllnesses ?? const [],
                            profile?.familyHistory,
                          ),
                        ),
                        const SeniorDivider(),
                        _FactRow(
                          label: '담배 · 술',
                          alwaysInline: true,
                          value: habitLine(),
                          missingLabel: missingProfileLabel,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 약을 드릴 때 조심할 것. 빨간 줄이 선 흰 카드.
class _WarnCard extends StatelessWidget {
  final String text;

  const _WarnCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return AccentCard(
      accent: AppColors.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '약을 드릴 때 조심할 것',
            style: AppText.cardTitle(size: 18, color: AppColors.danger),
          ),
          const SizedBox(height: 6),
          Text(text, style: AppText.emphasis(size: 23)),
          const SizedBox(height: 6),
          Text(
            '등록된 알레르기 정보예요. 약을 등록하거나 복용하기 전에 의사나 약사에게 알려 주세요.',
            style: AppText.body(size: 18),
          ),
        ],
      ),
    );
  }
}

/// 짧은 항목은 같은 열에 정렬하고, 좁은 화면/큰 글자/긴 내용은 위아래로 배치한다.
class _FactRow extends StatelessWidget {
  final String label;
  final String? value;
  final String missingLabel;
  final bool alwaysInline;

  const _FactRow({
    required this.label,
    this.value,
    this.missingLabel = '미입력',
    this.alwaysInline = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Text(
            label,
            style: AppText.label(size: 18, color: AppColors.textSecondary),
          );
          final content = Text(
            text.isEmpty ? missingLabel : text,
            style: text.isEmpty
                ? AppText.body(size: 18, color: AppColors.textTertiary)
                : AppText.cardTitle(size: 20),
          );
          final stacked =
              constraints.maxWidth < 260 ||
              MediaQuery.textScalerOf(context).scale(18) > 24 ||
              text.runes.length > 16 ||
              label.runes.length > 7 ||
              text.isEmpty;
          if (stacked && !alwaysInline) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 6), content],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: alwaysInline ? constraints.maxWidth * .3 : 100,
                child: title,
              ),
              const SizedBox(width: 12),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

/// 지금 드시는 약. 대신 처방전을 넣기 전에 무엇이 이미 들어가 있는지
/// 알아야 같은 약을 두 번 넣지 않는다.
class _MedicineListCard extends StatelessWidget {
  final AsyncValue<List<UserMedicine>> medicines;

  const _MedicineListCard({required this.medicines});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('지금 드시는 약', style: AppText.cardTitle(size: 21)),
          const SizedBox(height: 12),
          ...medicines.when(
            loading: () => [Text('불러오는 중이에요', style: AppText.body(size: 18))],
            // 못 읽었으면 못 읽었다고 말한다. 빈 목록으로 두면 드시는 약이
            // 없는 줄 알고 같은 약을 또 넣는다.
            error: (_, _) => [
              Text(
                '약 목록을 불러오지 못했어요',
                style: AppText.body(size: 18, color: AppColors.danger),
              ),
            ],
            data: (list) {
              final active = list.where((m) => m.status == 'active').toList();
              if (active.isEmpty) {
                return [Text('등록된 약이 없어요', style: AppText.body(size: 18))];
              }
              return [
                for (int i = 0; i < active.length; i++) ...[
                  if (i > 0) const SeniorDivider(),
                  _MedicineLine(medicine: active[i]),
                ],
              ];
            },
          ),
        ],
      ),
    );
  }
}

class _MedicineLine extends StatelessWidget {
  final UserMedicine medicine;

  const _MedicineLine({required this.medicine});

  @override
  Widget build(BuildContext context) {
    final slots = medicine.administrationTimes
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nameWithoutStrength(medicine.displayName),
            style: AppText.cardTitle(size: 20),
          ),
          if (medicine.amount.trim().isNotEmpty || slots.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (medicine.amount.trim().isNotEmpty) medicine.amount.trim(),
                if (slots.isNotEmpty) slots.join(' · '),
              ].join(' · '),
              style: AppText.caption(size: 17.5),
            ),
          ],
        ],
      ),
    );
  }
}
