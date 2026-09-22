import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../dashboard/presentation/screens/patient_data.dart';
import '../../application/guardians_provider.dart';

/// 보호자 화면 · 대신 찍기 — 어느 분 처방전인가요?
///
/// **처방전은 고른 분 한 분에게만 들어간다.** 여러 어르신을 함께 보는
/// 보호자가 엉뚱한 분에게 약을 넣는 일이 가장 무섭기 때문에, 찍기 전에
/// 어느 분인지부터 고르게 하고 이후 화면마다 그 이름을 계속 달고 다닌다.
class ProxyPatientPickerScreen extends ConsumerWidget {
  /// 어르신 한 분을 골랐을 때.
  final ValueChanged<CarePatient> onPick;

  const ProxyPatientPickerScreen({super.key, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(careOverviewProvider);
    final patients = overview.valueOrNull?.patients ?? const <CarePatient>[];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorHeader(
            child: Row(
              children: [
                const SeniorBackButton(),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('보호자 화면 · 대신 찍기', style: AppText.label(size: 17)),
                      Text(
                        '어느 분 처방전인가요?',
                        style: AppText.screenTitle(size: 28),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(careOverviewProvider.future),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (patients.isEmpty)
                      _EmptyCard(
                        loading: overview.isLoading,
                        failed: overview.hasError,
                        onRetry: () => ref.invalidate(careOverviewProvider),
                      )
                    else
                      for (final patient in patients) ...[
                        _PatientRow(
                          patient: patient,
                          onTap: () => onPick(patient),
                        ),
                        const SizedBox(height: 12),
                      ],
                    const SizedBox(height: 2),
                    SeniorCard(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('고른 분에게만 들어갑니다', style: AppText.cardTitle(size: 22)),
                          const SizedBox(height: 6),
                          Text(
                            '등록이 끝나면 그 어르신 전화기에 "약을 넣어드렸어요" 알림이 갑니다.',
                            style: AppText.body(size: 19),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "어머니 · 김복자" 한 줄.
class _PatientRow extends StatelessWidget {
  final CarePatient patient;
  final VoidCallback onTap;

  const _PatientRow({required this.patient, required this.onTap});

  /// 지금 서버가 주는 값으로 말할 수 있는 만큼만 적는다.
  /// 없는 숫자를 지어내면 보호자가 엉뚱한 분을 고른다.
  String get _subtitle {
    if (patient.totalCount <= 0) return '아직 등록된 약이 없어요';
    return '오늘 드실 약 ${patient.totalCount}가지';
  }

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      onTap: onTap,
      child: Row(
        children: [
          InitialAvatar(
            name: patient.name,
            size: 58,
            background: AppColors.pointTint,
            foreground: AppColors.point,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(patient.title, style: AppText.cardTitle(size: 22)),
                const SizedBox(height: 2),
                Text(_subtitle, style: AppText.caption(size: 17.5)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const SeniorChevron(),
        ],
      ),
    );
  }
}

/// 아직 연결된 어르신이 없거나 목록을 못 읽었을 때.
class _EmptyCard extends StatelessWidget {
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  const _EmptyCard({
    required this.loading,
    required this.failed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loading
                ? '돌보는 분을 불러오는 중이에요'
                : failed
                ? '돌보는 분 목록을 불러오지 못했어요'
                : '아직 연결된 어르신이 없어요. 먼저 어르신 계정을 만들거나 연결해 주세요.',
            style: AppText.body(size: 19),
          ),
          if (failed) ...[
            const SizedBox(height: 14),
            SeniorButton(
              label: '다시 불러오기',
              kind: SeniorButtonKind.secondary,
              minHeight: 60,
              fontSize: 20,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
