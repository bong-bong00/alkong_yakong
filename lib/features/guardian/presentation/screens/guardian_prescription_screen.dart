import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../dashboard/presentation/screens/patient_data.dart';
import '../../../prescription/presentation/screens/prescription_screen.dart';
import '../../application/guardians_provider.dart';
import '../../../dashboard/application/medication_calendar_provider.dart';
import '../../../medicines/application/user_medicines_controller.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../dashboard/application/medication_history_provider.dart';

/// 선택한 환자의 처방전 등록 방법 선택 화면을 연다.
Future<void> openGuardianPrescription(
  BuildContext context,
  CarePatient patient,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PrescriptionScreen(
        onBehalfOf: patient.title,
        onBehalfOfUserId: patient.patientId,
        onCompleted: (_) {
          final container = ProviderScope.containerOf(context, listen: false);
          container.invalidate(careOverviewProvider);
          container.invalidate(patientMedicinesProvider(patient.patientId));
          container.invalidate(patientTodayProvider(patient.patientId));
          container.invalidate(patientHistoryProvider(patient.patientId));
          container.invalidate(medicationMonthPlansProvider);
          Navigator.of(context).maybePop();
          if (!context.mounted) return;
          showSeniorSnackbar(context, '${patient.name} 님의 약과 복용 일정을 등록했어요');
        },
      ),
    ),
  );
}

/// 보호자 · 어느 분 처방전인가요 (프로토타입 96).
///
/// 대신 넣은 약은 **고른 분에게만** 들어간다. 잘못 고르면 남의 약이 된다.
class GuardianPickPatientScreen extends ConsumerWidget {
  const GuardianPickPatientScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(careOverviewProvider);
    final patients = overview.valueOrNull?.patients ?? const <CarePatient>[];

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          SeniorHeader(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SeniorBackButton(onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('처방전 대신 등록', style: AppText.label(size: 17)),
                      Text(
                        '어느 분 처방전인가요?',
                        style: AppText.screenTitle(size: 26),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (overview.isLoading && overview.valueOrNull == null)
                    Text('돌보는 분을 불러오는 중이에요', style: AppText.body(size: 18)),
                  if (overview.hasError) ...[
                    Text(
                      '환자 목록을 불러오지 못했어요. 연결 상태를 다시 확인해 주세요.',
                      style: AppText.body(size: 18),
                    ),
                    const SizedBox(height: 8),
                    SeniorButton(
                      label: '다시 불러오기',
                      kind: SeniorButtonKind.secondary,
                      fontSize: 18,
                      minHeight: 52,
                      onPressed: () => ref.invalidate(careOverviewProvider),
                    ),
                  ] else if (!overview.isLoading && patients.isEmpty)
                    Text(
                      '연결된 환자가 없어요. 설정 → 돌보는 분 관리에서 먼저 연결해 주세요.',
                      style: AppText.body(size: 18),
                    ),
                  for (final patient in patients) ...[
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      onTap: overview.hasError
                          ? null
                          : () => openGuardianPrescription(context, patient),
                      child: Row(
                        children: [
                          InitialAvatar(
                            name: patient.name,
                            size: 56,
                            background: AppColors.pointTint,
                            foreground: AppColors.point,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patient.title,
                                  style: AppText.cardTitle(size: 21),
                                ),
                                if (patient.totalCount > 0)
                                  Text(
                                    '오늘 먹을 약 ${patient.totalCount}번',
                                    style: AppText.caption(size: 17.5),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const SeniorChevron(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (patients.isNotEmpty && !overview.hasError)
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '선택한 환자의 약으로 등록돼요',
                            style: AppText.cardTitle(size: 21),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '등록이 끝나면 해당 환자의 앱에서도 약과 복용 일정을 확인할 수 있어요.',
                            style: AppText.body(size: 18),
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
