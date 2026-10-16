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
import '../../../guardian/application/guardians_provider.dart';
import '../../../guardian/application/guardian_alert_inbox.dart';
import '../../../guardian/data/alert_repository.dart';
import '../../../guardian/presentation/screens/care_family_screen.dart';
import '../../../guardian/presentation/screens/care_patient_screen.dart';
import '../../../guardian/application/prescription_help_inbox.dart';
import '../../../guardian/presentation/screens/guardian_info_screen.dart';
import '../../../guardian/presentation/screens/guardian_pharmacist_screen.dart';
import '../../../guardian/presentation/screens/guardian_prescription_screen.dart';
import '../../../../core/session/mvp_session.dart';
import '../../application/medication_history_provider.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medication/domain/medication_models.dart';
import 'medication_record_screen.dart';
import 'month_calendar_screen.dart';
import 'patient_data.dart';
import '../../../biosignal/data/heart_repository.dart';
import '../../../biosignal/presentation/screens/heart_screen.dart';
import '../../../medicines/application/user_medicines_controller.dart';

/// 보호자 쉘 — 돌보는 분 · AI 약사 · 설정에 바로 접근한다.
///
/// 알림은 목록 헤더의 종 단추로, 어르신 현황은 목록에서 눌러 들어간다.
/// 보호자 전용 남색 액센트는 폐기했다. 환자와 같은 파란 규칙을 쓰고,
/// 역할 구분은 탭 라벨과 상단 "보호자 화면" 라벨로만 한다.
class GuardianHomeScreen extends ConsumerStatefulWidget {
  /// 화면 확인용 임시 통로에서 가짜 알림을 넣을 때만 쓴다.
  final AlertRepository? alertsRepository;

  const GuardianHomeScreen({super.key, this.alertsRepository});

  @override
  ConsumerState<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends ConsumerState<GuardianHomeScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRefreshing();
  }

  void _startRefreshing() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _refreshRecords();
      }
    });
  }

  void _refreshRecords() {
    _askedAboutHelp = false;
    ref.invalidate(careOverviewProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshRecords();
      _startRefreshing();
    } else {
      _refreshTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  int _index = 0;
  int _pharmacistReturnIndex = 0;

  void _leavePharmacist() => setState(() => _index = _pharmacistReturnIndex);

  /// 부탁 팝업을 이번에 켠 동안 한 번만 본다.
  bool _askedAboutHelp = false;

  static const List<SeniorNavItem> _tabs = [
    SeniorNavItem(icon: TablerIcons.users, label: '돌보는 분'),
    SeniorNavItem(icon: TablerIcons.message_circle, label: 'AI 약사'),
    SeniorNavItem(icon: TablerIcons.settings, label: '설정'),
  ];

  /// 어르신이 "처방전 찍어 주세요"라고 부탁한 것이 있으면 바로 묻는다.
  ///
  /// 알림 목록을 열어 봐야 알 수 있으면 그 부탁은 며칠씩 묻힌다. 어르신은
  /// 그동안 약 없이 기다린다.
  Future<void> _maybeAskForPrescription(List<CarePatient> patients) async {
    if (_askedAboutHelp || patients.isEmpty) return;
    _askedAboutHelp = true;
    final owner = MvpSession.userId.trim();
    final repository = widget.alertsRepository ?? AlertRepository();

    for (final patient in patients) {
      final alerts = await repository.fetch(patient.patientId);
      if (!mounted) return;
      final ids = [
        for (final alert in alerts ?? const <AlertItem>[])
          if (alert.type == 'help' && alert.id != null) alert.id!,
      ];
      final fresh = await PrescriptionHelpInbox.unshown(owner, ids);
      if (!mounted) return;
      if (fresh.isEmpty) continue;

      await PrescriptionHelpInbox.markShown(owner, fresh);
      if (!mounted) return;
      final go = await showSeniorYesNoDialog(
        context: context,
        title: '${patient.title} 님이\n처방전을 부탁하셨어요',
        message: '처방전을 찍어서 보내 드리면 그 자리에서 약이 들어가요.',
        yesLabel: '처방전 대신 등록',
        noLabel: '나중에 할게요',
      );
      if (!go || !mounted) return;
      await openGuardianPrescription(context, patient);
      return;
    }
  }

  /// 어르신을 고르면 현황 화면을 연다. 탭을 바꾸지 않는다.
  void _openPatient(CarePatient patient) {
    final patients =
        ref.read(careOverviewProvider).valueOrNull?.patients ??
        const <CarePatient>[];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GuardianStatusScreen(
          patient: patient,
          position: patients.indexOf(patient) + 1,
          total: patients.length,
          alertsRepository: widget.alertsRepository,
        ),
      ),
    );
  }

  void _openAlerts() {
    final patients =
        ref.read(careOverviewProvider).valueOrNull?.patients ??
        const <CarePatient>[];
    if (patients.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GuardianAlertsScreen(
          patient: patients.first,
          patients: patients,
          repository: widget.alertsRepository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 돌보는 분 목록을 읽고 나서 부탁이 있는지 본다.
    ref.listen(careOverviewProvider, (_, next) {
      final patients = next.valueOrNull?.patients;
      if (patients != null && patients.isNotEmpty) {
        unawaited(_maybeAskForPrescription(patients));
      }
    });

    return PopScope(
      canPop: _index != 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index == 1) _leavePharmacist();
      },
      child: Scaffold(
        backgroundColor: AppColors.pageBg,
        body: IndexedStack(
          index: _index,
          children: [
            CareFamilyScreen(
              onOpenPatient: _openPatient,
              onOpenAlerts: _openAlerts,
            ),
            GuardianPharmacistScreen(onBack: _leavePharmacist),
            const GuardianInfoScreen(),
          ],
        ),
        bottomNavigationBar: SeniorBottomNav(
          items: _tabs,
          currentIndex: _index,
          onTap: (i) => setState(() {
            if (i == 1 && _index != 1) _pharmacistReturnIndex = _index;
            _index = i;
          }),
        ),
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
//  보호자 · 어르신 현황 (프로토타입 88)
// ════════════════════════════════════════════════════════════════

/// 보호자가 할 수 있는 일: 조회 · 전화 · 대신 등록.
/// **대신 복약 체크는 할 수 없다** — 오기록을 막기 위해서다.
class GuardianStatusScreen extends ConsumerStatefulWidget {
  final CarePatient patient;
  final HeartRepository? heartRepository;

  /// 목록에서 몇 번째 분인지. "3명 중 1번째"로 읽힌다.
  final int position;
  final int total;

  final AlertRepository? alertsRepository;

  const GuardianStatusScreen({
    super.key,
    required this.patient,
    required this.position,
    required this.total,
    this.alertsRepository,
    this.heartRepository,
  });

  @override
  ConsumerState<GuardianStatusScreen> createState() =>
      _GuardianStatusScreenState();
}

class _GuardianStatusScreenState extends ConsumerState<GuardianStatusScreen>
    with WidgetsBindingObserver {
  Timer? _poll;
  HeartRepository? get heartRepository => widget.heartRepository;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) _refresh();
    });
  }

  void _refresh() {
    ref.invalidate(careOverviewProvider);
    ref.invalidate(patientTodayProvider(widget.patient.patientId));
    ref.invalidate(patientMedicinesProvider(widget.patient.patientId));
    ref.invalidate(patientHistoryProvider(widget.patient.patientId));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _start();
    } else {
      _poll?.cancel();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 그 시간대를 드신 시각 — "8시 10분". 기록이 없으면 null.
  ///
  /// 값은 서버가 슬롯마다 실어 보낸 것만 쓴다. "오늘 있었던 일" 글귀를
  /// 문자열로 뒤져 찾으면 그 글귀가 한 글자만 바뀌어도 시각이 조용히 사라진다.
  static String? _takenAt(CareSlot slot) {
    if (!slot.taken) return null;
    final moment = DateTime.tryParse(slot.time)?.toLocal();
    if (moment != null) return DoseSlot.absoluteTime(moment);
    final parts = slot.time.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return minute == 0 ? '$hour시' : '$hour시 $minute분';
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(careOverviewProvider);
    final matching = overview.valueOrNull?.patients
        .where((p) => p.patientId == widget.patient.patientId)
        .toList();
    if (overview.hasValue && matching?.isEmpty == true) {
      return Scaffold(
        body: Column(
          children: [
            SeniorBackHeader(title: widget.patient.title),
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('환자 연결을 확인할 수 없어요. 돌보는 분 목록에서 다시 확인해 주세요.'),
            ),
          ],
        ),
      );
    }
    final patient = matching?.isNotEmpty == true
        ? matching!.first
        : widget.patient;
    final slots = patient.slots;
    final heartRate = patient.heartRate;
    final medicineList = ref.watch(patientMedicinesProvider(patient.patientId));
    final todayState = ref.watch(patientTodayProvider(patient.patientId));
    // 복약 달력은 어르신 화면과 같은 것을 쓴다. 보호자가 보는 그림과
    // 어르신이 보는 그림이 다르면 통화로 맞춰 볼 수가 없다.
    final today = todayState.valueOrNull ?? TodayMedication.empty;
    final history =
        ref.watch(patientHistoryProvider(patient.patientId)).valueOrNull ??
        const <DateTime, DayAdherence>{};

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          SeniorHeader(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SeniorBackButton(onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '${patient.title} 님',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.screenTitle(size: 26),
                  ),
                ),
              ],
            ),
          ),
          // ── 6. 당겨서 새로고침을 두지 않는다 ──
          // 내용이 화면에 들어오는데도 늘 끌리게 만들어야 해서, 스크롤할
          // 것이 없는데 화면이 몇 px씩 들썩였다.
          // 단추를 뺀 만큼 한 화면에 들어온다. 글자를 크게 키운 기기에서만
          // 넘치는 만큼 밀린다.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (patient.needsAttention) ...[
                    _AttentionCard(
                      text:
                          '${patient.overdueDoseLabel ?? patient.nextDoseLabel} 복용 완료 기록이 아직 없어요',
                      onCall: () => _callPatient(context, patient),
                    ),
                    const SizedBox(height: 14),
                  ],
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        if (slots.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              todayState.hasError ||
                                      today.fetchStatus ==
                                          MedicationFetchStatus.failed ||
                                      medicineList.hasError
                                  ? '복용 정보를 불러오지 못했어요. 다시 확인해 주세요.'
                                  : todayState.isLoading ||
                                        medicineList.isLoading
                                  ? '복용 정보를 확인하고 있어요…'
                                  : medicineList.valueOrNull?.isEmpty == true
                                  ? '등록된 약이 없어요. 처방전을 등록해 주세요.'
                                  : '오늘 예정된 복용 일정이 없어요.',
                              style: AppText.body(size: 18),
                            ),
                          ),
                        for (int i = 0; i < slots.length; i++) ...[
                          if (i > 0) const SeniorDivider(),
                          _StatusRow(
                            icon: slots[i].taken
                                ? TablerIcons.circle_check_filled
                                : TablerIcons.circle,
                            iconColor: slots[i].taken
                                ? AppColors.textPrimary
                                : slots[i].recordStatus == 'overdue'
                                ? AppColors.danger
                                : AppColors.textTertiary,
                            label: '${slots[i].label} 약',
                            value:
                                _takenAt(slots[i]) ??
                                (slots[i].taken
                                    ? '완료'
                                    : slots[i].recordStatus == 'overdue'
                                    ? '기록 없음'
                                    : slots[i].recordStatus == 'scheduled'
                                    ? '예정'
                                    : '시간 확인'),
                            danger: slots[i].recordStatus == 'overdue',
                          ),
                        ],
                        if (heartRate != null) ...[
                          if (slots.isNotEmpty) const SeniorDivider(),
                          _StatusRow(
                            icon: TablerIcons.heart,
                            iconColor: AppColors.point,
                            label: '최근 심박수',
                            value: '${heartRate}bpm',
                            status: heartRate < 60
                                ? '느림'
                                : heartRate > 100
                                ? '빠름'
                                : '정상',
                            statusColor: heartRate < 60 || heartRate > 100
                                ? AppColors.danger
                                : AppColors.textSecondary,
                            singleLine: true,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              patient.heartRateTimeLabel,
                              style: AppText.caption(size: 16),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (slots.isEmpty && heartRate == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        '오늘 온 기록이 아직 없어요.',
                        style: AppText.body(size: 18),
                      ),
                    ),
                  const SizedBox(height: 12),
                  // 처음엔 이번 주만. "달력으로 보기"를 누르면 한 달로 넓힌다.
                  if (patient.patientId.trim().isNotEmpty) ...[
                    SeniorCard(
                      key: const Key('guardian-open-heart-records'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HeartScreen(
                            userId: patient.patientId,
                            patientTitle: patient.title,
                            repository: heartRepository,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            TablerIcons.heart,
                            size: 28,
                            color: AppColors.point,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '심박수 기록 보기',
                              style: AppText.cardTitle(size: 21),
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  AdherenceWeekCard(
                    days: weekAdherenceStatuses(today, history),
                    onOpenCalendar: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MonthCalendarScreen(
                          patientUserId: patient.patientId,
                        ),
                      ),
                    ),
                    onPickDay: (status) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MonthCalendarScreen(
                          patientUserId: patient.patientId,
                          year: status.date.year,
                          month: status.date.month,
                          initialDay: status.date.day,
                        ),
                      ),
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

/// 빨간 줄이 선 흰 카드. 프로토타입 88의 "확인이 필요해요".
class _AttentionCard extends StatelessWidget {
  final String text;
  final VoidCallback onCall;

  const _AttentionCard({required this.text, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return AccentCard(
      accent: AppColors.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '확인이 필요해요',
            style: AppText.cardTitle(size: 18, color: AppColors.danger),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppText.emphasis(size: 23),
          ),
          const SizedBox(height: 14),
          SeniorButton(
            label: '전화 드리기',
            icon: TablerIcons.phone,
            kind: SeniorButtonKind.neutral,
            minHeight: 62,
            fontSize: 21,
            onPressed: onCall,
          ),
        ],
      ),
    );
  }
}

/// 아침 약 · 8시 10분처럼 한 줄.
class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool danger;
  final bool singleLine;
  final String? status;
  final Color? statusColor;

  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.danger = false,
    this.singleLine = false,
    this.status,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, size: 28, color: iconColor)),
          const SizedBox(width: 14),
          if (singleLine)
            Expanded(
              flex: 6,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: AppText.cardTitle(size: 21),
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                label,
                style: AppText.cardTitle(
                  size: 21,
                  color: danger ? AppColors.danger : AppColors.textPrimary,
                ),
              ),
            ),
          const SizedBox(width: 10),
          Flexible(
            flex: singleLine ? 5 : 1,
            fit: FlexFit.tight,
            child: singleLine
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: value),
                          if (status != null)
                            TextSpan(
                              text: '($status)',
                              style: TextStyle(color: statusColor),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      softWrap: false,
                      style: AppText.cardTitle(
                        size: 16,
                        color: danger
                            ? AppColors.danger
                            : AppColors.textSecondary,
                      ),
                    ),
                  )
                : Text(
                    value,
                    textAlign: TextAlign.end,
                    style: AppText.cardTitle(
                      size: 20,
                      color: danger
                          ? AppColors.danger
                          : AppColors.textSecondary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  4k — 알림
// ════════════════════════════════════════════════════════════════

/// "확인했어요"는 미확인 목록에서 제외한다. 복약 완료 기록과는 별개다.
/// 어르신 쪽 재알림 사다리도 계속 진행된다.
class GuardianAlertsTab extends ConsumerStatefulWidget {
  final CarePatient patient;
  final List<CarePatient>? patients;

  /// 알림을 읽어 올 곳. 없으면 이 탭이 하나 만들어 쓴다.
  final AlertRepository? repository;

  const GuardianAlertsTab({
    super.key,
    required this.patient,
    this.repository,
    this.patients,
  });

  @override
  ConsumerState<GuardianAlertsTab> createState() => _GuardianAlertsTabState();
}

class _GuardianAlertsTabState extends ConsumerState<GuardianAlertsTab> {
  Timer? _poll;
  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  final Set<int> _acknowledged = <int>{};
  final Map<AlertItem, CarePatient> _owners = {};
  late final _inbox = GuardianAlertInbox(MvpSession.userId);
  bool _showAcknowledged = false;
  Future<void> _acknowledge(int? id, CarePatient patient) async {
    if (id == null) return;
    try {
      await _inbox.acknowledge(patient.patientId, id);
      if (!mounted) return;
      setState(() => _acknowledged.add(id));
      ref.read(guardianAlertRevisionProvider.notifier).state++;
    } catch (_) {
      if (mounted) {
        showSeniorSnackbar(
          context,
          '확인 표시를 저장하지 못했어요. 다시 확인해 주세요.',
          error: true,
        );
      }
    }
  }

  late final AlertRepository _repository =
      widget.repository ?? ref.read(guardianAlertRepositoryProvider);

  List<AlertItem>? _loaded;
  bool _failed = false;

  /// 별일이 없다는 말은 알림으로 띄우지 않는다.
  ///
  /// "일주일 동안 모두 정상이었어요" 같은 줄이 쌓이면, 정작 손이 가야 할
  /// 알림이 그 사이에 묻힌다. 알림은 할 일이 있을 때만 온다.
  static bool _worthTelling(AlertItem alert) {
    const actionable = {
      'help',
      'miss',
      'alert',
      'refill',
      'prescription',
      'done',
      'shared',
      'past',
    };
    if (!actionable.contains(alert.type)) return false;
    if (alert.type == 'alert' && alert.desc.contains('모두 정상이었어요')) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        unawaited(_load());
      }
    });
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final combined = <AlertItem>[];
    final owners = <AlertItem, CarePatient>{};
    var failed = false;
    for (final patient in widget.patients ?? [widget.patient]) {
      try {
        _acknowledged.addAll(await _inbox.read(patient.patientId));
      } catch (_) {
        failed = true;
      }
      final items = await _repository.fetch(patient.patientId);
      if (items == null) {
        failed = true;
        continue;
      }
      for (final alert in items.where(_worthTelling)) {
        combined.add(alert);
        owners[alert] = patient;
      }
    }
    if (!mounted) return;
    // 못 읽으면 못 읽었다고 말한다. 예시 알림으로 갈아끼우지 않는다.
    setState(() {
      _owners
        ..clear()
        ..addAll(owners);
      _loaded = failed ? null : combined;
      _failed = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _loaded
        ?.where(
          (a) =>
              _showAcknowledged ==
              _acknowledged.contains(GuardianAlertInbox.identity(a)),
        )
        .toList();
    return Column(
      children: [
        if (_loaded != null)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textTertiary,
              textStyle: AppText.body(
                size: 15,
              ).copyWith(fontWeight: FontWeight.w400),
              minimumSize: const Size(48, 48),
            ),
            onPressed: () =>
                setState(() => _showAcknowledged = !_showAcknowledged),
            child: Text(_showAcknowledged ? '미확인 알림 보기' : '확인한 알림 보기'),
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
                          vertical: 14,
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
                    itemCount: alerts.isEmpty ? 1 : alerts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (alerts.isEmpty) {
                        return Text(
                          _showAcknowledged ? '확인한 알림이 없어요.' : '확인할 알림이 없어요.',
                          textAlign: TextAlign.center,
                          style: AppText.caption(size: 17),
                        );
                      }
                      final notificationId = GuardianAlertInbox.identity(
                        alerts[index],
                      );
                      return _AlertCard(
                        alert: alerts[index],
                        patient: _owners[alerts[index]] ?? widget.patient,
                        acknowledged: _acknowledged.contains(notificationId),
                        onAcknowledge: () => unawaited(
                          _acknowledge(
                            notificationId,
                            _owners[alerts[index]] ?? widget.patient,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// 목록 헤더의 종 단추로 들어오는 알림 화면 (프로토타입 89).
class GuardianAlertsScreen extends StatelessWidget {
  final CarePatient patient;
  final List<CarePatient>? patients;
  final AlertRepository? repository;

  const GuardianAlertsScreen({
    super.key,
    required this.patient,
    this.patients,
    this.repository,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '알림', alignStart: true),
          Expanded(
            child: GuardianAlertsTab(
              patient: patient,
              patients: patients,
              repository: repository,
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

  const _AlertCard({
    required this.alert,
    required this.patient,
    required this.acknowledged,
    required this.onAcknowledge,
  });

  bool get _isDanger =>
      alert.type == 'miss' || alert.type == 'alert' || alert.type == 'refill';

  Color get _statusColor {
    if (acknowledged || alert.type == 'past') return AppColors.textTertiary;
    return _isDanger ? AppColors.danger : AppColors.point;
  }

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.all(20),
      radius: 20,
      child: _content(context),
    );
  }

  /// 누구 알림인지 — "어머니(김복자)". 호칭을 모르면 이름만.
  String get _who => patient.relation.isEmpty
      ? patient.name
      : '${patient.relation}(${patient.name})';

  /// 무슨 일인지. 서버 글귀가 "어머니가 …"로 시작하면 그 앞부분을 덜어낸다
  /// — 누구인지는 윗줄이 이미 말한다.
  String get _what {
    var text = alert.desc.trim();
    for (final name in [patient.relation, patient.name, _who]) {
      if (name.isEmpty) continue;
      for (final josa in ['가 ', '이 ', '은 ', '는 ', '님이 ', '님은 ']) {
        final head = '$name$josa';
        if (text.startsWith(head)) return text.substring(head.length).trim();
      }
    }
    return text;
  }

  Widget _content(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _who,
                style: AppText.cardTitle(
                  size: 18,
                  color: AppColors.textPrimary,
                  weight: FontWeight.w600,
                ),
                // 첫 줄 위에 남는 행간을 끈다. 마지막 줄 아래도 껐으므로
                // 글자와 카드 사이가 위아래 같은 폭으로 떨어진다.
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                ),
              ),
            ),
            Text(
              alert.time,
              style: AppText.label(size: 14, color: AppColors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _what,
          style: AppText.label(size: 20, color: AppColors.textBody),
          // 행간(1.5)의 아래쪽 몫이 마지막 줄 밑에 남아, 같은 여백인데도
          // 아래가 더 벌어져 보인다. 마지막 줄의 아래 행간만 끈다.
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToLastDescent: false,
          ),
        ),
        if (alert.type == 'help') ...[
          const SizedBox(height: 14),
          SeniorButton(
            label: '처방전 대신 등록',
            minHeight: 60,
            fontSize: 20,
            onPressed: () => openGuardianPrescription(context, patient),
          ),
        ],
        if (alert.type == 'prescription') ...[
          Align(
            alignment: Alignment.centerLeft,
            // 새로 들어온 약은 현황이 아니라 명단에서 손본다.
            child: SeniorTextButton(
              label: '돌보는 분 관리에서 보기',
              expand: false,
              fontSize: 19,
              color: AppColors.point,
              // 목록을 한 번 더 거치지 않고 그 어르신 화면으로 바로 간다.
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CarePatientScreen(patient: patient),
                ),
              ),
            ),
          ),
        ],
        // 확인한 뒤에는 단추를 남기지 않는다. "확인함"이 눌리지 않는 채로
        // 남아 있으면 아직 할 일이 있는 것처럼 보인다.
        if (!acknowledged) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SeniorButton(
                  label: '전화 드리기',
                  kind: SeniorButtonKind.secondary,
                  minHeight: 56,
                  fontSize: 19,
                  onPressed: () => _callPatient(context, patient),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SeniorButton(
                  label: '확인했어요',
                  kind: SeniorButtonKind.secondary,
                  minHeight: 56,
                  fontSize: 19,
                  onPressed: onAcknowledge,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
