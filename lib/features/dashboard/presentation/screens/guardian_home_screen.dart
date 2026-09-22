import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_bottom_nav.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../biosignal/presentation/screens/heart_screen.dart';
import '../../../guardian/application/guardians_provider.dart';
import '../../../guardian/data/alert_repository.dart';
import '../../../guardian/presentation/screens/care_family_screen.dart';
import '../../../profile/presentation/screens/mypage_screen.dart';
import 'medication_record_screen.dart';
import 'patient_data.dart';

/// 보호자 쉘 — 탭은 **돌보는 분 · 현황 · 알림 · 내 정보** 넷이다.
///
/// 보호자 전용 남색 액센트는 폐기했다. 환자와 같은 파란 규칙을 쓰고,
/// 역할 구분은 탭 라벨과 상단 "보호자 화면" 라벨로만 한다.
class GuardianHomeScreen extends ConsumerStatefulWidget {
  const GuardianHomeScreen({super.key});

  @override
  ConsumerState<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends ConsumerState<GuardianHomeScreen> {
  int _index = 0;

  /// 지금 보고 있는 어르신. 목록이 새로 와도 같은 분을 계속 본다.
  String? _patientId;

  static const List<SeniorNavItem> _tabs = [
    SeniorNavItem(icon: TablerIcons.activity, label: '현황'),
    SeniorNavItem(icon: TablerIcons.bell, label: '알림'),
    SeniorNavItem(icon: TablerIcons.users, label: '돌보는 분'),
    SeniorNavItem(icon: TablerIcons.user, label: '내 정보'),
  ];

  /// 돌보는 분 목록에서 한 분을 고르면 현황 탭으로 넘어간다.
  void _openPatient(CarePatient patient) {
    setState(() {
      _patientId = patient.patientId;
      _index = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final patients =
        ref.watch(careOverviewProvider).valueOrNull?.patients ??
        const <CarePatient>[];
    final selected =
        patients.where((p) => p.patientId == _patientId).firstOrNull ??
        patients.firstOrNull;
    void backToFamily() => setState(() => _index = 2);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _index,
        children: [
          selected == null
              ? _NoPatientTab(onBackToFamily: backToFamily)
              : GuardianStatusTab(
                  patient: selected,
                  position: patients.indexOf(selected) + 1,
                  total: patients.length,
                  onBackToFamily: backToFamily,
                  onOpenAlerts: () => setState(() => _index = 1),
                ),
          selected == null
              ? _NoPatientTab(onBackToFamily: backToFamily)
              : GuardianAlertsTab(
                  key: ValueKey(selected.patientId),
                  patient: selected,
                  onOpenStatus: () => setState(() => _index = 0),
                ),
          CareFamilyScreen(onOpenPatient: _openPatient),
          const MyPageScreen(isGuardian: true),
        ],
      ),
      bottomNavigationBar: SeniorBottomNav(
        items: _tabs,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// 아직 볼 어르신이 없을 때. 목록으로 돌아가는 길만 내민다.
class _NoPatientTab extends StatelessWidget {
  final VoidCallback onBackToFamily;

  const _NoPatientTab({required this.onBackToFamily});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SeniorTitleHeader(title: '보호자 화면'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: SeniorCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('아직 연결된 어르신이 없어요', style: AppText.cardTitle(size: 21)),
                  const SizedBox(height: 8),
                  Text(
                    '어르신이 수락하면 여기에서 복약과 심장 박동을 볼 수 있어요.',
                    style: AppText.body(size: 18),
                  ),
                  const SizedBox(height: 14),
                  SeniorButton(
                    label: '돌보는 분 목록으로',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 58,
                    fontSize: 20,
                    onPressed: onBackToFamily,
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

/// 어르신 번호로 전화 앱을 연다. 번호가 없거나 못 열면 그렇다고 말한다.
Future<void> _callPatient(BuildContext context, CarePatient patient) async {
  final digits = (patient.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    showSeniorSnackbar(
      context,
      '${patient.name} 님 전화번호가 등록돼 있지 않아요',
      error: true,
    );
    return;
  }
  var opened = false;
  try {
    opened = await launchUrl(Uri(scheme: 'tel', path: digits));
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    showSeniorSnackbar(context, '전화 앱을 열지 못했어요', error: true);
  }
}

// ════════════════════════════════════════════════════════════════
//  4j — 부모님 현황
// ════════════════════════════════════════════════════════════════

/// 보호자가 할 수 있는 일: 조회 · 전화 · 알림 확인.
/// **대신 복약 체크는 할 수 없다** — 오기록을 막기 위해서다.
class GuardianStatusTab extends ConsumerWidget {
  final CarePatient patient;

  /// 목록에서 몇 번째 분인지. "3명 중 1번째"로 읽힌다.
  final int position;
  final int total;

  final VoidCallback onBackToFamily;
  final VoidCallback onOpenAlerts;

  const GuardianStatusTab({
    super.key,
    required this.patient,
    required this.position,
    required this.total,
    required this.onBackToFamily,
    required this.onOpenAlerts,
  });

  String get _doseNote {
    if (patient.totalCount == 0) return '등록된 약이 없어요';
    return patient.needsAttention
        ? '${patient.nextDoseLabel}이 남아 있어요'
        : '오늘 약을 다 드셨어요';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardianTitle = patient.relation.isEmpty
        ? '${patient.name} 님'
        : '${patient.relation} ${patient.name} 님';
    final weekRate = patient.weekRate;

    return Column(
      children: [
        SeniorHeader(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SeniorBackButton(onTap: onBackToFamily),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '보호자 화면 · $total명 중 $position번째',
                      style: AppText.label(size: 17),
                    ),
                    Text(patient.title, style: AppText.screenTitle(size: 26)),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 오늘 복약 ──
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 17,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '오늘 복약',
                          style: AppText.label(
                            size: 19,
                            weight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${patient.takenCount} / ${patient.totalCount}',
                              style: AppText.hero(size: 44),
                            ),
                            Text(
                              _doseNote,
                              style: AppText.label(
                                size: 19,
                                color: AppColors.point,
                              ),
                            ),
                          ],
                        ),
                        if (patient.slots.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              for (
                                int i = 0;
                                i < patient.slots.length;
                                i++
                              ) ...[
                                if (i > 0) const SizedBox(width: 10),
                                Expanded(
                                  child: _SlotChip(
                                    label: patient.slots[i].label,
                                    done: patient.slots[i].taken,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 지표 분할 ──
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HeartScreen(
                          userId: patient.patientId,
                          guardianTitle: guardianTitle,
                        ),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: _Metric(
                              label: '심박수',
                              value: patient.heartRate?.toString() ?? '-',
                              note: patient.heartRate == null
                                  ? '측정 기록 없음'
                                  : patient.heartRateNormal == false
                                  ? '확인 필요'
                                  : '정상',
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 52,
                            color: AppColors.divider,
                          ),
                          Expanded(
                            child: _Metric(
                              label: '이번 주',
                              value: weekRate == null ? '-' : '$weekRate%',
                              note: weekRate == null ? '기록 없음' : '복약',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 확인 필요 ──
                  if (patient.needsAttention) ...[
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      borderColor: AppColors.dangerBorder,
                      borderWidth: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppColors.danger,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  '확인이 필요해요',
                                  style: AppText.cardTitle(
                                    size: 18,
                                    color: AppColors.danger,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${patient.nextDoseLabel}을 아직 안 드셨어요',
                            style: AppText.cardTitle(size: 21),
                          ),
                          const SizedBox(height: 14),
                          SeniorButton(
                            label: '전화 드리기',
                            minHeight: 62,
                            fontSize: 21,
                            onPressed: () => _callPatient(context, patient),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── 오늘 있었던 일 ──
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('오늘 있었던 일', style: AppText.cardTitle(size: 20)),
                        const SizedBox(height: 12),
                        if (patient.activities.isEmpty)
                          Text(
                            '오늘은 아직 들어온 기록이 없어요',
                            style: AppText.body(size: 18),
                          ),
                        for (int i = 0; i < patient.activities.length; i++) ...[
                          if (i > 0) ...[
                            const SizedBox(height: 12),
                            const SeniorDivider(),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  patient.activities[i].text,
                                  style: AppText.body(
                                    size: 18.5,
                                    color: AppColors.textBody,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                patient.activities[i].time,
                                style: AppText.label(
                                  size: 17,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 약 목록 · 처방전 대신 등록 ──
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '약 목록 · 처방전 대신 등록',
                          style: AppText.cardTitle(size: 20),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '보호자 계정에서는 어르신 화면이 열리지 않습니다. '
                          '대신 등록한 약은 어르신 화면에 알림으로만 전달돼요.',
                          style: AppText.body(size: 17.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 복약 기록 · 알림 ──
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        SeniorListRow(
                          label: '복약 기록 보기',
                          icon: TablerIcons.file_text,
                          trailing: const SeniorChevron(),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                backgroundColor: AppColors.bg,
                                body: MedicationRecordScreen(
                                  patientName: patient.name,
                                  patientUserId: patient.patientId,
                                  showBack: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SeniorDivider(),
                        SeniorListRow(
                          label: '지난 알림 보기',
                          icon: TablerIcons.bell,
                          trailing: const SeniorChevron(),
                          onTap: onOpenAlerts,
                        ),
                        if ((patient.phone ?? '').isNotEmpty) ...[
                          const SeniorDivider(),
                          SeniorListRow(
                            label: '전화 드리기',
                            icon: TablerIcons.phone,
                            value: patient.phone,
                            trailing: const SeniorChevron(),
                            onTap: () => _callPatient(context, patient),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '보호자는 대신 복약 체크를 할 수 없어요.\n'
                    '어르신이 직접 누르신 기록만 남습니다.',
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

class _SlotChip extends StatelessWidget {
  final String label;
  final bool done;
  const _SlotChip({required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: done ? AppColors.pointTint : AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: done
            ? null
            : Border.all(color: AppColors.strongBorder, width: 2),
      ),
      child: Text(
        label,
        style: AppText.label(
          size: 18,
          color: done ? AppColors.point : AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String note;

  const _Metric({required this.label, required this.value, required this.note});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption(size: 17)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                style: AppText.bigTime(size: 34),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                note,
                style: AppText.caption(size: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  4k — 알림
// ════════════════════════════════════════════════════════════════

/// "확인했어요"는 알림을 읽음 처리할 뿐 **삭제하지 않는다**.
/// 어르신 쪽 재알림 사다리도 계속 진행된다.
class GuardianAlertsTab extends StatefulWidget {
  final CarePatient patient;

  /// 알림을 읽어 올 곳. 없으면 이 탭이 하나 만들어 쓴다.
  final AlertRepository? repository;

  /// "현황에서 보기"를 눌렀을 때 건너갈 곳.
  final VoidCallback? onOpenStatus;

  const GuardianAlertsTab({
    super.key,
    required this.patient,
    this.repository,
    this.onOpenStatus,
  });

  @override
  State<GuardianAlertsTab> createState() => _GuardianAlertsTabState();
}

class _GuardianAlertsTabState extends State<GuardianAlertsTab> {
  final Set<int> _acknowledged = <int>{};

  late final AlertRepository _repository =
      widget.repository ?? AlertRepository();

  List<AlertItem>? _loaded;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final loaded = await _repository.fetch(widget.patient.patientId);
    if (!mounted) return;
    // 못 읽으면 못 읽었다고 말한다. 예시 알림으로 갈아끼우지 않는다.
    setState(() {
      _loaded = loaded;
      _failed = loaded == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _loaded;
    return Column(
      children: [
        SeniorHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.patient.name} 님', style: AppText.label(size: 17)),
              Text('알림', style: AppText.screenTitle(size: 28)),
            ],
          ),
        ),
        Expanded(
          child: alerts == null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SeniorCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _failed ? '알림을 불러오지 못했어요' : '불러오는 중이에요',
                              style: AppText.body(size: 18),
                            ),
                            if (_failed) ...[
                              const SizedBox(height: 12),
                              SeniorButton(
                                label: '다시 불러오기',
                                kind: SeniorButtonKind.secondary,
                                minHeight: 58,
                                fontSize: 20,
                                onPressed: _load,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    itemCount: alerts.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == alerts.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            alerts.isEmpty
                                ? '아직 온 알림이 없어요.'
                                : '"확인했어요"는 읽음 처리만 합니다.\n'
                                      '어르신 쪽 재알림은 계속 진행돼요.',
                            textAlign: TextAlign.center,
                            style: AppText.caption(size: 17),
                          ),
                        );
                      }
                      return _AlertCard(
                        alert: alerts[index],
                        patient: widget.patient,
                        acknowledged: _acknowledged.contains(index),
                        onAcknowledge: () =>
                            setState(() => _acknowledged.add(index)),
                        onOpenStatus: widget.onOpenStatus,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AlertItem alert;
  final CarePatient patient;
  final bool acknowledged;
  final VoidCallback onAcknowledge;

  /// 새 처방전 알림에서 현황 탭으로 건너가는 길.
  final VoidCallback? onOpenStatus;

  const _AlertCard({
    required this.alert,
    required this.patient,
    required this.acknowledged,
    required this.onAcknowledge,
    this.onOpenStatus,
  });

  bool get _isDanger =>
      alert.type == 'miss' || alert.type == 'alert' || alert.type == 'refill';

  Color get _barColor {
    if (_isDanger) return AppColors.danger;
    // 지난 것은 회색으로 뒤로 물린다. 지우지는 않는다.
    if (alert.type == 'past') return AppColors.strongLine;
    return AppColors.point;
  }

  @override
  Widget build(BuildContext context) {
    // 색 막대는 **카드 안쪽**에 세운다. 카드 모서리로 잘라내면 막대의
    // 위아래가 곡선에 먹혀 비스듬히 잘린 토막처럼 보인다.
    return SeniorCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 22, 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: _barColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: _content(context)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                alert.title,
                style: AppText.cardTitle(size: 18, color: _barColor),
              ),
            ),
            Text(
              alert.time,
              style: AppText.label(size: 17, color: AppColors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          alert.desc,
          style: AppText.label(size: 20.5, color: AppColors.textPrimary),
        ),
        if (alert.type == 'prescription' && onOpenStatus != null) ...[
          const SizedBox(height: 10),
          SeniorTextButton(
            label: '현황에서 보기',
            color: AppColors.point,
            expand: false,
            onPressed: onOpenStatus,
          ),
        ],
        if (_isDanger) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SeniorButton(
                  label: '전화 드리기',
                  minHeight: 56,
                  fontSize: 19,
                  onPressed: () => _callPatient(context, patient),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SeniorButton(
                  label: acknowledged ? '확인함' : '확인했어요',
                  kind: SeniorButtonKind.secondary,
                  minHeight: 56,
                  fontSize: 19,
                  onPressed: acknowledged ? null : onAcknowledge,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
