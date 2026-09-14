import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../dashboard/presentation/screens/patient_data.dart';
import '../../application/guardians_provider.dart';
import '../../data/guardian_repository.dart';
import '../widgets/add_care_sheet.dart';

/// 36 · 보호자 · 돌보는 분 목록.
///
/// 서버에 연결된 어르신만 보여준다. 연결을 요청한 분은 어르신이 수락할 때까지
/// "수락을 기다리는 중"으로 따로 둔다 — 동의 없이 남의 복약을 들여다보는 길을
/// 만들지 않는다.
class CareFamilyScreen extends ConsumerWidget {
  /// 어르신 카드를 눌렀을 때.
  final ValueChanged<CarePatient> onOpenPatient;

  /// 요청을 보낼 곳. 없으면 이 화면이 하나 만들어 쓴다.
  final GuardianRepository? repository;

  const CareFamilyScreen({
    super.key,
    required this.onOpenPatient,
    this.repository,
  });

  GuardianRepository get _repository => repository ?? GuardianRepository();

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final draft = await showAddCareSheet(context);
    if (draft == null || !context.mounted) return;

    final result = await _repository.requestLink(
      relation: draft.relation,
      phone: draft.phone,
    );
    if (!context.mounted) return;

    // 서버가 받아 준 뒤에만 목록에 올린다. 실패했는데 올려 두면
    // 어르신은 요청을 받은 적이 없는데 보호자만 기다리게 된다.
    if (!result.isSent) {
      showSeniorSnackbar(context, result.error ?? '연결을 요청하지 못했어요');
      return;
    }
    ref.invalidate(careOverviewProvider);
    final name = result.invite!.name.isEmpty ? draft.name : result.invite!.name;
    showSeniorSnackbar(context, '$name 님에게 연결을 요청했어요');
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    PendingInvite invite,
  ) async {
    final id = invite.id;
    if (id == null) return;
    try {
      await _repository.remove(id);
      ref.invalidate(careOverviewProvider);
    } on ApiException catch (error) {
      if (context.mounted) showSeniorSnackbar(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(careOverviewProvider);
    final data = overview.valueOrNull;
    final patients = data?.patients ?? const <CarePatient>[];
    final pending = data?.pending ?? const <PendingInvite>[];
    final needAttention = patients.where((p) => p.needsAttention).toList();

    return Column(
      children: [
        SeniorHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('보호자 화면', style: AppText.label(size: 17)),
              Text(
                data == null ? '돌보는 분' : '돌보는 분 ${patients.length}명',
                style: AppText.screenTitle(size: 28),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(careOverviewProvider.future),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (data == null && overview.isLoading)
                    const _InfoCard(text: '불러오는 중이에요')
                  else if (data == null)
                    _InfoCard(
                      text: '돌보는 분 목록을 불러오지 못했어요',
                      actionLabel: '다시 불러오기',
                      onAction: () => ref.invalidate(careOverviewProvider),
                    )
                  else if (patients.isEmpty && pending.isEmpty)
                    const _InfoCard(
                      text: '아직 연결된 어르신이 없어요. 아래 "돌보는 분 추가하기"에서 '
                          '어르신 전화번호로 연결을 요청해 주세요.',
                    ),
                  if (needAttention.isNotEmpty) ...[
                    _AttentionBanner(patients: needAttention),
                    const SizedBox(height: 12),
                  ],
                  for (int i = 0; i < patients.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _PatientCard(
                      patient: patients[i],
                      onTap: () => onOpenPatient(patients[i]),
                    ),
                  ],
                  for (final invite in pending) ...[
                    const SizedBox(height: 12),
                    _PendingCard(
                      invite: invite,
                      onCancel: () => _cancel(context, ref, invite),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SeniorButton(
                    label: '돌보는 분 추가하기',
                    icon: TablerIcons.user_plus,
                    kind: SeniorButtonKind.secondary,
                    minHeight: 64,
                    fontSize: 21,
                    onPressed: () => _add(context, ref),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '보호자 계정에서는 어르신 화면이 열리지 않습니다',
                    textAlign: TextAlign.center,
                    style: AppText.caption(size: 17),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InfoCard({required this.text, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text, style: AppText.body(size: 18)),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            SeniorButton(
              label: actionLabel!,
              kind: SeniorButtonKind.secondary,
              minHeight: 58,
              fontSize: 20,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

/// 먼저 확인할 분. 색이 아니라 **이름**을 앞세운다.
class _AttentionBanner extends StatelessWidget {
  final List<CarePatient> patients;

  const _AttentionBanner({required this.patients});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: AppColors.danger),
            Expanded(
              child: Container(
                color: AppColors.dangerBgSoft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '먼저 확인할 분',
                      style: AppText.cardTitle(
                        size: 18,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final patient in patients)
                      Text(patient.title, style: AppText.cardTitle(size: 20)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final CarePatient patient;
  final VoidCallback onTap;

  const _PatientCard({required this.patient, required this.onTap});

  String get _status {
    if (patient.totalCount == 0) return '오늘 드실 약이 등록돼 있지 않아요.';
    if (patient.needsAttention) {
      return '${patient.nextDoseLabel} 기록이 아직 오지 않았어요.';
    }
    return patient.heartRateNormal == true
        ? '오늘 약을 다 드셨어요. 심장 박동도 정상입니다.'
        : '오늘 약을 다 드셨어요.';
  }

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                    Text(patient.title, style: AppText.cardTitle(size: 21)),
                    Text(
                      '오늘 복약 ${patient.takenCount} / ${patient.totalCount}'
                      '${patient.heartRate == null ? '' : ' · 심박수 ${patient.heartRate}'}',
                      style: AppText.caption(size: 17.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const SeniorChevron(),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.sunken,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(_status, style: AppText.label(size: 18)),
          ),
        ],
      ),
    );
  }
}

/// 아직 수락하지 않은 요청. 점선 테두리로 "아직 아님"을 눈에 보이게 한다.
class _PendingCard extends StatelessWidget {
  final PendingInvite invite;
  final VoidCallback onCancel;

  const _PendingCard({required this.invite, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final title = invite.relation.isEmpty
        ? invite.name
        : '${invite.relation} · ${invite.name}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.strongLine, width: 2),
      ),
      child: Row(
        children: [
          const ExcludeSemantics(
            child: Icon(
              TablerIcons.hourglass_high,
              size: 26,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardTitle(size: 20)),
                Text(
                  '${invite.phone} · 수락을 기다리는 중',
                  style: AppText.caption(size: 17),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SeniorTextButton(
            label: '취소',
            expand: false,
            fontSize: 18,
            color: AppColors.textTertiary,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
