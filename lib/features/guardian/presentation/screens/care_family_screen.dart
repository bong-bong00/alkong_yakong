import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../dashboard/presentation/screens/patient_data.dart';
import '../../data/guardian_repository.dart';
import '../widgets/add_care_sheet.dart';

/// 36 · 보호자 · 돌보는 분 목록.
///
/// 보호자는 여러 어르신을 볼 수 있다. 그런데 설정은 **한 분씩 따로** 저장된다 —
/// 알림 시간도, 재알림 사다리도, 전화 대상도. 그 사실을 화면에 적어 두지 않으면
/// 한 분에게 바꾼 설정이 모두에게 적용된 줄 안다.
class CareFamilyScreen extends StatefulWidget {
  final List<PatientData> patients;

  /// 어르신 카드를 눌렀을 때. 목록에서 몇 번째인지 넘긴다.
  final ValueChanged<int> onOpenPatient;

  /// 초대를 보낼 곳. 없으면 이 화면이 하나 만들어 쓴다.
  final GuardianRepository? repository;

  const CareFamilyScreen({
    super.key,
    this.patients = DemoPatients.all,
    required this.onOpenPatient,
    this.repository,
  });

  @override
  State<CareFamilyScreen> createState() => _CareFamilyScreenState();
}

class _CareFamilyScreenState extends State<CareFamilyScreen> {
  late List<PendingInvite> _pending = List.of(DemoPatients.pending);

  late final GuardianRepository _repository =
      widget.repository ?? GuardianRepository();

  /// 오늘 약이 남은 분들. 목록 맨 위에 이름만 먼저 올린다.
  List<PatientData> get _needAttention => widget.patients
      .where((p) => p.takenCount < p.totalCount)
      .toList();

  Future<void> _add() async {
    final draft = await showAddCareSheet(context);
    if (draft == null || !mounted) return;

    final result = await _repository.invite(
      name: draft.name,
      relation: draft.relation,
      phone: draft.phone,
    );
    if (!mounted) return;

    // 서버가 받아 준 뒤에만 목록에 올린다. 실패했는데 올려 두면
    // 어르신은 초대를 받은 적이 없는데 보호자만 기다리게 된다.
    if (!result.isSent) {
      showSeniorSnackbar(context, result.error ?? '초대를 보내지 못했어요');
      return;
    }
    setState(() => _pending = [..._pending, result.invite!]);
    showSeniorSnackbar(context, '${result.invite!.name} 님에게 초대를 보냈어요');
  }

  void _cancel(PendingInvite invite) {
    setState(() => _pending = _pending.where((p) => p != invite).toList());
  }

  @override
  Widget build(BuildContext context) {
    final needAttention = _needAttention;

    return Column(
      children: [
        SeniorHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('보호자 화면', style: AppText.label(size: 17)),
              Text(
                '돌보는 분 ${widget.patients.length}명',
                style: AppText.screenTitle(size: 28),
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
                if (needAttention.isNotEmpty) ...[
                  _AttentionBanner(patients: needAttention),
                  const SizedBox(height: 12),
                ],
                for (int i = 0; i < widget.patients.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _PatientCard(
                    patient: widget.patients[i],
                    onTap: () => widget.onOpenPatient(i),
                  ),
                ],
                for (final invite in _pending) ...[
                  const SizedBox(height: 12),
                  _PendingCard(invite: invite, onCancel: () => _cancel(invite)),
                ],
                const SizedBox(height: 12),
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '한 분씩 따로 설정돼요',
                        style: AppText.cardTitle(size: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '알림 시간, 재알림 사다리, 전화 대상은 어르신마다 따로 '
                        '저장됩니다. 형제·자매가 같은 어르신을 함께 볼 수도 있어요.',
                        style: AppText.body(size: 17.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SeniorButton(
                  label: '돌보는 분 추가하기',
                  icon: TablerIcons.user_plus,
                  kind: SeniorButtonKind.secondary,
                  minHeight: 64,
                  fontSize: 21,
                  onPressed: _add,
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
      ],
    );
  }
}

/// 먼저 확인할 분. 색이 아니라 **이름**을 앞세운다.
class _AttentionBanner extends StatelessWidget {
  final List<PatientData> patients;

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
                      Text(
                        '${patient.relation} · ${patient.name}',
                        style: AppText.cardTitle(size: 20),
                      ),
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
  final PatientData patient;
  final VoidCallback onTap;

  const _PatientCard({required this.patient, required this.onTap});

  String get _status {
    if (patient.takenCount >= patient.totalCount) {
      return '오늘 약을 다 드셨어요. 심장 박동도 정상입니다.';
    }
    return '${patient.nextDose} 기록이 아직 오지 않았어요.';
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
                    Text(
                      '${patient.relation} · ${patient.name}',
                      style: AppText.cardTitle(size: 21),
                    ),
                    Text(
                      '오늘 복약 ${patient.takenCount} / ${patient.totalCount}'
                      ' · 심박수 ${patient.currentHr}',
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

/// 아직 수락하지 않은 초대. 점선 테두리로 "아직 아님"을 눈에 보이게 한다.
class _PendingCard extends StatelessWidget {
  final PendingInvite invite;
  final VoidCallback onCancel;

  const _PendingCard({required this.invite, required this.onCancel});

  @override
  Widget build(BuildContext context) {
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
                Text(
                  '${invite.relation} · ${invite.name}',
                  style: AppText.cardTitle(size: 20),
                ),
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
