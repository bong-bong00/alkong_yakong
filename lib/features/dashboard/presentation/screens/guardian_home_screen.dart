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
import '../../../prescription/domain/proxy_target.dart';
import '../../../prescription/presentation/screens/prescription_screen.dart';
import '../../../profile/presentation/screens/mypage_screen.dart';
import 'medication_record_screen.dart';
import 'patient_data.dart';

/// 보호자 쉘 — 탭은 **돌보는 분 · 정보** 둘이다.
///
/// 한 분의 현황과 알림은 탭이 아니라 눌러서 들어가는 화면이다. 탭으로
/// 두면 "지금 누구를 보고 있는지"가 탭 밖에 숨어, 어머니를 보다가
/// 알림 탭을 누르면 아버지 알림이 뜨는 일이 생긴다.
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

  static const List<SeniorNavItem> _tabs = [
    SeniorNavItem(icon: TablerIcons.users, label: '돌보는 분'),
    SeniorNavItem(icon: TablerIcons.user, label: '정보'),
  ];

  List<CarePatient> get _patients =>
      ref.read(careOverviewProvider).valueOrNull?.patients ??
      const <CarePatient>[];

  /// 목록에서 한 분을 고르면 그분의 현황으로 들어간다.
  void _openPatient(CarePatient patient) {
    final patients = _patients;
    final index = patients.indexWhere((p) => p.patientId == patient.patientId);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GuardianStatusScreen(
          patient: patient,
          position: index < 0 ? 1 : index + 1,
          total: patients.isEmpty ? 1 : patients.length,
        ),
      ),
    );
  }

  /// 머리의 종. 돌보는 분 모두의 알림을 한자리에서 본다.
  void _openAlerts() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GuardianAlertsScreen(patients: _patients),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _index,
        children: [
          CareFamilyScreen(
            onOpenPatient: _openPatient,
            onOpenAlerts: _openAlerts,
          ),
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

/// 보호자가 할 수 있는 일: 조회 · 전화 · 대신 찍기.
/// **대신 복약 체크는 할 수 없다** — 오기록을 막기 위해서다.
class GuardianStatusScreen extends ConsumerWidget {
  final CarePatient patient;

  /// 목록에서 몇 번째 분인지. "3명 중 1번째"로 읽힌다.
  final int position;
  final int total;

  const GuardianStatusScreen({
    super.key,
    required this.patient,
    required this.position,
    required this.total,
  });

  /// 어르신 대신 처방전을 찍는다. 등록은 이 어르신 앞으로 올라간다.
  Future<void> _capture(BuildContext context, WidgetRef ref) async {
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PrescriptionScreen(
          proxyTarget: ProxyTarget(
            patientId: patient.patientId,
            title: patient.title,
          ),
        ),
      ),
    );
    if (registered == true) ref.invalidate(careOverviewProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardianTitle = patient.relation.isEmpty
        ? '${patient.name} 님'
        : '${patient.relation} ${patient.name} 님';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorHeader(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SeniorBackButton(),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 확인이 필요해요 ──
                    // 할 일이 있을 때만 세운다. 늘 붉은 띠가 서 있으면
                    // 그 띠는 곧 배경이 되어 아무도 읽지 않는다.
                    if (patient.needsAttention) ...[
                      _AttentionCard(
                        headline: '${patient.nextDoseLabel}을 아직 안 드셨어요',
                        onCall: () => _callPatient(context, patient),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── 오늘 ──
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          if (patient.slots.isEmpty)
                            const _TodayRow(
                              label: '오늘 드실 약',
                              value: '등록된 약이 없어요',
                              state: _RowState.none,
                            ),
                          for (final slot in patient.slots)
                            _TodayRow(
                              label: '${slot.label} 약',
                              // 시각은 어르신이 누른 기록에서만 온다.
                              // 기록이 없으면 "드셨어요"까지만 말한다.
                              value: slot.taken
                                  ? (slot.time.isEmpty
                                        ? '드셨어요'
                                        : _spokenClock(slot.time))
                                  : '아직',
                              state: slot.taken
                                  ? _RowState.done
                                  : _RowState.waiting,
                            ),
                          _TodayRow(
                            label: '심박수',
                            value: patient.heartRate == null
                                ? '잰 기록 없어요'
                                : '${patient.heartRate}'
                                      '${_heartNote(patient.heartRateNormal)}',
                            state: patient.heartRate == null
                                ? _RowState.none
                                : _RowState.heart,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => HeartScreen(
                                  userId: patient.patientId,
                                  guardianTitle: guardianTitle,
                                ),
                              ),
                            ),
                          ),
                          if (patient.weekRate case final int rate)
                            _TodayRow(
                              label: '이번 주 복약',
                              value: '$rate%',
                              state: _RowState.none,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── 복약 기록 · 알림 · 전화 ──
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
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    GuardianAlertsScreen(patients: [patient]),
                              ),
                            ),
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
          // 여기서 할 수 있는 단 하나의 일. 바닥에 붙여 늘 손에 닿게 둔다.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SeniorButton(
                label: '처방전 대신 찍기',
                icon: TablerIcons.camera,
                minHeight: 70,
                onPressed: () => _capture(context, ref),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "08:10" → "8시 10분". 읽는 대로 들리게 적는다.
  static String _spokenClock(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return raw;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return raw;
    return minute == 0 ? '$hour시' : '$hour시 $minute분';
  }

  static String _heartNote(bool? normal) => switch (normal) {
    true => ' 정상',
    false => ' 확인 필요',
    null => '',
  };
}

/// 붉은 띠를 세운 카드 하나. 지금 손이 가야 할 일만 여기에 적는다.
class _AttentionCard extends StatelessWidget {
  final String headline;
  final VoidCallback onCall;

  const _AttentionCard({required this.headline, required this.onCall});

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
                    '확인이 필요해요',
                    style: AppText.cardTitle(size: 18, color: AppColors.danger),
                  ),
                  const SizedBox(height: 8),
                  Text(headline, style: AppText.cardTitle(size: 23)),
                  const SizedBox(height: 14),
                  SeniorButton(
                    label: '전화 드리기',
                    icon: TablerIcons.phone,
                    kind: SeniorButtonKind.secondary,
                    minHeight: 62,
                    fontSize: 21,
                    onPressed: onCall,
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

enum _RowState { done, waiting, heart, none }

/// 오늘 한 줄 — 왼쪽 표시, 가운데 이름, 오른쪽 값.
class _TodayRow extends StatelessWidget {
  final String label;
  final String value;
  final _RowState state;
  final VoidCallback? onTap;

  const _TodayRow({
    required this.label,
    required this.value,
    required this.state,
    this.onTap,
  });

  Color get _ink => switch (state) {
    _RowState.waiting => AppColors.danger,
    _RowState.none => AppColors.textTertiary,
    _ => AppColors.textPrimary,
  };

  Widget get _mark => switch (state) {
    _RowState.done => const Icon(
      TablerIcons.circle_check_filled,
      size: 30,
      color: AppColors.textPrimary,
    ),
    _RowState.waiting => const Icon(
      TablerIcons.circle,
      size: 30,
      color: AppColors.danger,
    ),
    _RowState.heart => const Icon(
      TablerIcons.heart_filled,
      size: 28,
      color: AppColors.point,
    ),
    _RowState.none => const SizedBox(width: 30),
  };

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          ExcludeSemantics(child: _mark),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: AppText.cardTitle(size: 21, color: _ink),
            ),
          ),
          const SizedBox(width: 10),
          Text(value, style: AppText.label(size: 20, color: _ink)),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const SeniorChevron(),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: row,
    );
  }
}

/// 돌보는 분들에게서 온 알림을 한자리에 모아 보여준다.
///
/// 한 분만 넘기면 그분 것만 본다 — 현황에서 "지난 알림 보기"로 들어올 때다.
class GuardianAlertsScreen extends StatefulWidget {
  final List<CarePatient> patients;

  /// 알림을 읽어 올 곳. 없으면 이 화면이 하나 만들어 쓴다.
  final AlertRepository? repository;

  const GuardianAlertsScreen({
    super.key,
    required this.patients,
    this.repository,
  });

  @override
  State<GuardianAlertsScreen> createState() => _GuardianAlertsScreenState();
}

class _GuardianAlertsScreenState extends State<GuardianAlertsScreen> {
  final Set<String> _acknowledged = <String>{};

  late final AlertRepository _repository =
      widget.repository ?? AlertRepository();

  /// 알림과 그 알림이 누구 것인지. 전화를 걸 상대가 알림마다 다르다.
  List<(AlertItem, CarePatient)>? _loaded;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final rows = <(AlertItem, CarePatient)>[];
    // 한 분이라도 못 읽으면 못 읽었다고 말한다. 반쪽짜리 목록을 보여주면
    // 보호자는 나머지 분에게는 아무 일도 없었다고 믿는다.
    var failed = widget.patients.isEmpty;
    for (final patient in widget.patients) {
      final loaded = await _repository.fetch(patient.patientId);
      if (loaded == null) {
        failed = true;
        continue;
      }
      for (final alert in loaded) {
        rows.add((alert, patient));
      }
    }
    if (!mounted) return;
    setState(() {
      _loaded = failed && rows.isEmpty ? null : rows;
      _failed = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _loaded;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '알림'),
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
                      final (alert, patient) = alerts[index];
                      final key = '${patient.patientId}#$index';
                      return _AlertCard(
                        alert: alert,
                        patient: patient,
                        // 여러 분을 함께 볼 때는 누구 알림인지 밝힌다.
                        showWho: widget.patients.length > 1,
                        acknowledged: _acknowledged.contains(key),
                        onAcknowledge: () =>
                            setState(() => _acknowledged.add(key)),
                        onOpenStatus: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => GuardianStatusScreen(
                              patient: patient,
                              position: 1,
                              total: 1,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AlertItem alert;
  final CarePatient patient;
  final bool acknowledged;
  final VoidCallback onAcknowledge;

  /// 여러 분의 알림을 함께 볼 때, 누구 알림인지 밝힌다.
  final bool showWho;

  /// 새 처방전 알림에서 그분 현황으로 건너가는 길.
  final VoidCallback? onOpenStatus;

  const _AlertCard({
    required this.alert,
    required this.patient,
    this.showWho = false,
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
          // 알림 글귀가 이미 "어머니가 …"로 시작하면 호칭을 겹쳐 쓰지 않는다.
          showWho && !alert.desc.startsWith(patient.relation)
              ? '${patient.title} · ${alert.desc}'
              : alert.desc,
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
