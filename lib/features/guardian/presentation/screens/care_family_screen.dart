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
import '../../../prescription/domain/proxy_target.dart';
import '../../../prescription/presentation/screens/prescription_screen.dart';
import '../../../profile/domain/user_profile.dart';
import '../../application/guardians_provider.dart';
import '../../data/guardian_repository.dart';
import '../../domain/proxy_signup.dart';
import '../widgets/add_care_sheet.dart';
import 'proxy_patient_picker_screen.dart';
import 'proxy_signup_screen.dart';

// ════════════════════════════════════════════════════════════════
//  목록과 관리 화면이 함께 쓰는 길
// ════════════════════════════════════════════════════════════════

/// 어르신 전화번호로 연결을 요청한다.
Future<void> addCarePatient(
  BuildContext context,
  WidgetRef ref, {
  GuardianRepository? repository,
}) async {
  final draft = await showAddCareSheet(context);
  if (draft == null || !context.mounted) return;

  final result = await (repository ?? GuardianRepository()).requestLink(
    relation: draft.relation,
    phone: draft.phone,
  );
  if (!context.mounted) return;

  // 서버가 받아 준 뒤에만 목록에 올린다. 실패했는데 올려 두면
  // 어르신은 요청을 받은 적이 없는데 보호자만 기다리게 된다.
  if (!result.isSent) {
    showSeniorSnackbar(context, result.error ?? '연결을 요청하지 못했어요', error: true);
    return;
  }
  ref.invalidate(careOverviewProvider);
  final name = result.invite!.name.isEmpty ? draft.name : result.invite!.name;
  showSeniorSnackbar(context, '$name 님에게 연결을 요청했어요');
}

/// 어르신 계정을 자녀분이 대신 만든다. 다 만들면 바로 대신 찍기로 이어진다.
Future<void> createElderAccount(BuildContext context, WidgetRef ref) async {
  await Navigator.of(context).push(
    MaterialPageRoute<ProxySignupResult>(
      builder: (_) => ProxySignupScreen(
        onCapturePrescription: (result) {
          // 가입 화면을 닫고 그 자리에서 처방전 찍기로 넘어간다.
          Navigator.of(context).pop();
          captureFor(
            context,
            ref,
            ProxyTarget(patientId: result.patientId, title: result.title),
          );
        },
      ),
    ),
  );
  ref.invalidate(careOverviewProvider);
}

/// 어느 분 처방전인지 먼저 고르고 찍는다.
Future<void> pickPatientAndCapture(BuildContext context, WidgetRef ref) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (pickerContext) => ProxyPatientPickerScreen(
        onPick: (patient) {
          Navigator.of(pickerContext).pop();
          captureFor(
            context,
            ref,
            ProxyTarget(patientId: patient.patientId, title: patient.title),
          );
        },
      ),
    ),
  );
}

/// 그 어르신 앞으로 처방전을 찍어 올린다.
Future<void> captureFor(
  BuildContext context,
  WidgetRef ref,
  ProxyTarget target,
) async {
  final registered = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => PrescriptionScreen(proxyTarget: target),
    ),
  );
  if (registered == true) ref.invalidate(careOverviewProvider);
}

// ════════════════════════════════════════════════════════════════
//  36 · 보호자 · 돌보는 분
// ════════════════════════════════════════════════════════════════

/// 아침에 여는 화면. **오늘 누가 약을 안 드셨나**만 본다.
///
/// 명단 손질(대신 가입·연결 요청)은 [CareManageScreen]으로 옮겼다. 매일
/// 여는 자리에 "추가하기"가 서 있으면 목록보다 그 버튼이 먼저 읽힌다.
///
/// 서버에 연결된 어르신만 보여준다. 연결을 요청한 분은 어르신이 수락할 때까지
/// "수락을 기다리는 중"으로 따로 둔다 — 동의 없이 남의 복약을 들여다보는 길을
/// 만들지 않는다.
class CareFamilyScreen extends ConsumerWidget {
  /// 어르신 카드를 눌렀을 때.
  final ValueChanged<CarePatient> onOpenPatient;

  /// 머리의 종을 눌렀을 때. 없으면 종을 그리지 않는다.
  final VoidCallback? onOpenAlerts;

  /// 요청을 보낼 곳. 없으면 이 화면이 하나 만들어 쓴다.
  final GuardianRepository? repository;

  const CareFamilyScreen({
    super.key,
    required this.onOpenPatient,
    this.onOpenAlerts,
    this.repository,
  });

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    PendingInvite invite,
  ) async {
    final id = invite.id;
    if (id == null) return;
    try {
      await (repository ?? GuardianRepository()).remove(id);
      ref.invalidate(careOverviewProvider);
    } on ApiException catch (error) {
      if (context.mounted) {
        showSeniorSnackbar(context, error.message, error: true);
      }
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
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
              if (onOpenAlerts case final VoidCallback open) ...[
                const SizedBox(width: 12),
                _AlertBell(count: needAttention.length, onTap: open),
              ],
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
                      text:
                          '아직 연결된 어르신이 없어요. 아래 "돌보는 분 추가하기"에서 '
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
                  if (patients.isEmpty) ...[
                    const SizedBox(height: 16),
                    // 어르신이 혼자 가입하다 막히는 것이 첫 이탈 지점이다.
                    // 아직 아무도 없을 때는 이 길을 맨 앞에 내민다.
                    SeniorButton(
                      label: '가족이 회원가입해주기',
                      subLabel: '어르신 대신 작성이 가능해요',
                      icon: TablerIcons.user_plus,
                      minHeight: 76,
                      fontSize: 22,
                      onPressed: () => createElderAccount(context, ref),
                    ),
                    const SizedBox(height: 12),
                    SeniorButton(
                      label: '돌보는 분 추가하기',
                      icon: TablerIcons.user_plus,
                      kind: SeniorButtonKind.secondary,
                      minHeight: 64,
                      fontSize: 21,
                      onPressed: () => addCarePatient(context, ref),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    SeniorButton(
                      label: '처방전 대신 찍어드리기',
                      icon: TablerIcons.camera,
                      kind: SeniorButtonKind.secondary,
                      minHeight: 64,
                      fontSize: 21,
                      onPressed: () => pickPatientAndCapture(context, ref),
                    ),
                  ],
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

// ════════════════════════════════════════════════════════════════
//  돌보는 분 관리 — 명단을 손질하는 자리
// ════════════════════════════════════════════════════════════════

class CareManageScreen extends ConsumerWidget {
  const CareManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patients =
        ref.watch(careOverviewProvider).valueOrNull?.patients ??
        const <CarePatient>[];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '돌보는 분 관리'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Text(
                      '한 분씩 따로 설정돼요',
                      style: AppText.cardTitle(size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (patients.isEmpty)
                    const _InfoCard(text: '아직 연결된 어르신이 없어요')
                  else
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < patients.length; i++) ...[
                            if (i > 0) const SeniorDivider(),
                            _ManageRow(patient: patients[i]),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                children: [
                  SeniorButton(
                    label: '가족이 회원가입해주기',
                    subLabel: '어르신 대신 작성이 가능해요',
                    icon: TablerIcons.user_plus,
                    kind: SeniorButtonKind.secondary,
                    minHeight: 68,
                    fontSize: 21,
                    onPressed: () => createElderAccount(context, ref),
                  ),
                  const SizedBox(height: 12),
                  SeniorButton(
                    label: '돌보는 분 추가하기',
                    icon: TablerIcons.user_plus,
                    minHeight: 70,
                    onPressed: () => addCarePatient(context, ref),
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

/// 관리 목록 한 줄 — 얼굴, 호칭·이름, 그리고 아는 만큼의 한 줄.
class _ManageRow extends StatelessWidget {
  final CarePatient patient;

  const _ManageRow({required this.patient});

  /// "79세". 생년월일을 모르면 전화번호로, 그마저 없으면 빈 글자.
  /// 모르는 것을 채워 넣지 않는다.
  String get _subtitle {
    if (patient.age case final int age) return '$age세';
    return patient.phone ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CarePatientProfileScreen(patient: patient),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            InitialAvatar(
              name: patient.name,
              size: 52,
              background: AppColors.pointTint,
              foreground: AppColors.point,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patient.title, style: AppText.cardTitle(size: 21)),
                  if (_subtitle.isNotEmpty)
                    Text(_subtitle, style: AppText.caption(size: 17.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SeniorChevron(),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  어르신 한 분의 몸 정보
// ════════════════════════════════════════════════════════════════

/// 대신 약을 넣기 전에 읽어야 할 것들.
///
/// 맨 위는 **알레르기**다. 그 아래 연세·키·병력은 참고지만, 알레르기는
/// 모르고 넣으면 사람이 다친다.
class CarePatientProfileScreen extends ConsumerStatefulWidget {
  final CarePatient patient;

  /// 프로필을 읽어 올 곳. 없으면 이 화면이 하나 만들어 쓴다.
  final ApiClient? apiClient;

  const CarePatientProfileScreen({
    super.key,
    required this.patient,
    this.apiClient,
  });

  @override
  ConsumerState<CarePatientProfileScreen> createState() =>
      _CarePatientProfileScreenState();
}

class _CarePatientProfileScreenState
    extends ConsumerState<CarePatientProfileScreen> {
  late final ApiClient _apiClient = widget.apiClient ?? ApiClient();

  UserProfile? _profile;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final response = await _apiClient.get(
        '/api/v1/users/${Uri.encodeComponent(widget.patient.patientId)}',
      );
      if (!mounted) return;
      if (response is! Map) {
        setState(() => _failed = true);
        return;
      }
      setState(
        () => _profile = UserProfile.fromJson(
          Map<String, dynamic>.from(response),
        ),
      );
    } catch (_) {
      // 못 읽으면 못 읽었다고 말한다. 빈 칸을 "없음"으로 적지 않는다.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final facts = profile == null ? const <(String, String)>[] : _facts(profile);
    final history = profile == null
        ? const <(String, String)>[]
        : _history(profile);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorBackHeader(title: widget.patient.title),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (profile == null)
                    _InfoCard(
                      text: _failed ? '어르신 정보를 불러오지 못했어요' : '불러오는 중이에요',
                      actionLabel: _failed ? '다시 불러오기' : null,
                      onAction: _failed ? _load : null,
                    )
                  else ...[
                    if (profile.allergies.isNotEmpty) ...[
                      _AllergyCard(allergies: profile.allergies),
                      const SizedBox(height: 12),
                    ],
                    if (facts.isNotEmpty)
                      SeniorCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            for (int i = 0; i < facts.length; i++) ...[
                              if (i > 0) const SeniorDivider(),
                              _FactRow(
                                label: facts[i].$1,
                                value: facts[i].$2,
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (profile.diseases.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SeniorCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '지금 앓고 있는 병',
                              style: AppText.label(
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final disease in profile.diseases)
                                  _DiseaseChip(label: disease),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (history.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SeniorCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            for (int i = 0; i < history.length; i++) ...[
                              if (i > 0) const SeniorDivider(),
                              _StackedFact(
                                label: history[i].$1,
                                value: history[i].$2,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '어르신이 가입할 때 적으신 내용이에요.\n'
                    '보호자 화면에서는 고칠 수 없습니다.',
                    textAlign: TextAlign.center,
                    style: AppText.caption(size: 17),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 아는 것만 줄로 만든다. 모르는 값은 줄 자체를 만들지 않는다.
  List<(String, String)> _facts(UserProfile profile) {
    final rows = <(String, String)>[];
    if (widget.patient.age case final int age) rows.add(('연세', '$age세'));
    if (profile.birthDate case final DateTime birth) {
      rows.add(('생년월일', '${birth.year}년 ${birth.month}월 ${birth.day}일'));
    }
    if (_genderLabel(profile.gender) case final String gender) {
      rows.add(('성별', gender));
    }
    final height = profile.heightCm;
    final weight = profile.weightKg;
    if (height != null || weight != null) {
      rows.add((
        '키 · 몸무게',
        [
          if (height != null) '${_trim(height)}cm',
          if (weight != null) '${_trim(weight)}kg',
        ].join(' · '),
      ));
    }
    if (profile.bloodType case final String blood when blood.isNotEmpty) {
      rows.add(('혈액형', blood.endsWith('형') ? blood : '$blood형'));
    }
    if (profile.phone case final String phone when phone.isNotEmpty) {
      rows.add(('연락처', phone));
    }
    return rows;
  }

  List<(String, String)> _history(UserProfile profile) {
    final rows = <(String, String)>[];
    // 서버는 "있었는지"만 담는다. 무슨 병이었는지는 모르므로 지어내지 않는다.
    if (profile.pastHistory case final bool past) {
      rows.add(('크게 아팠던 적', past ? '있으세요' : '없으세요'));
    }
    if (profile.familyHistory case final bool family) {
      rows.add(('가족 병력', family ? '있으세요' : '없으세요'));
    }
    final smoking = profile.smoking;
    final drinking = profile.drinking;
    if ((smoking ?? '').isNotEmpty || (drinking ?? '').isNotEmpty) {
      rows.add((
        '담배 · 술',
        [
          if ((smoking ?? '').isNotEmpty) '담배 $smoking',
          if ((drinking ?? '').isNotEmpty) '술 $drinking',
        ].join(' · '),
      ));
    }
    return rows;
  }

  static String? _genderLabel(String? gender) => switch (gender) {
    'F' => '여자',
    'M' => '남자',
    _ => null,
  };

  static String _trim(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

/// 약을 드릴 때 조심할 것. 이 화면에서 가장 먼저 읽혀야 한다.
class _AllergyCard extends StatelessWidget {
  final List<String> allergies;

  const _AllergyCard({required this.allergies});

  @override
  Widget build(BuildContext context) {
    // 색 막대는 카드 안쪽에 세운다. 모서리로 잘라내면 비스듬히 잘린다.
    return SeniorCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 22, 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '약을 드릴 때 조심할 것',
                    style: AppText.cardTitle(size: 18, color: AppColors.danger),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${allergies.join(', ')} 알레르기가 있어요',
                    style: AppText.cardTitle(size: 23),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '새 처방전을 대신 넣을 때 이 약이 들어 있으면 화면이 먼저 알려드려요.',
                    style: AppText.body(size: 17.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 라벨은 왼쪽, 값은 오른쪽 끝.
class _FactRow extends StatelessWidget {
  final String label;
  final String value;

  const _FactRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.label(size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppText.cardTitle(size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// 라벨 아래에 값을 내려 적는다. 값이 길어 오른쪽 끝에 붙지 않을 때 쓴다.
class _StackedFact extends StatelessWidget {
  final String label;
  final String value;

  const _StackedFact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.label(size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(value, style: AppText.cardTitle(size: 20)),
        ],
      ),
    );
  }
}

class _DiseaseChip extends StatelessWidget {
  final String label;

  const _DiseaseChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.pointTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label, style: AppText.label(size: 19, color: AppColors.point)),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  조각들
// ════════════════════════════════════════════════════════════════

/// 머리의 종. 손이 가야 할 알림이 몇 건인지 붉은 점으로 얹는다.
class _AlertBell extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _AlertBell({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: count == 0 ? '알림' : '알림 $count건',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.secondaryFill,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    TablerIcons.bell,
                    size: 28,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (count > 0)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$count',
                        style: AppText.button(size: 16, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
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
    return SeniorCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 20, 18),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '먼저 확인할 분',
                    style: AppText.cardTitle(size: 18, color: AppColors.danger),
                  ),
                  const SizedBox(height: 6),
                  // 호칭만 쉼표로 잇는다. 이름까지 줄줄이 쓰면 띠가 길어져
                  // "먼저"라는 말이 무색해진다.
                  Text(
                    [
                      for (final patient in patients)
                        patient.relation.isEmpty
                            ? patient.name
                            : patient.relation,
                    ].join(', '),
                    style: AppText.cardTitle(size: 20),
                  ),
                ],
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
    if (patient.totalCount == 0) return '오늘 드실 약이 등록돼 있지 않아요';
    if (patient.needsAttention) return '${patient.nextDoseLabel}이 남아 있어요';
    return '오늘 ${_spokenCount(patient.totalCount)} 다 드셨어요';
  }

  /// "세 번"처럼 읽어 준다. 숫자보다 말이 먼저 들어온다.
  static String _spokenCount(int count) {
    const words = ['', '한 번', '두 번', '세 번', '네 번', '다섯 번'];
    if (count >= 1 && count < words.length) return words[count];
    return '$count번';
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
