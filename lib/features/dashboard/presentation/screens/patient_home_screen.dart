import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../dev_mock.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/coach_marks.dart';
import '../../../../core/widgets/help_button.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/session/presentation_history.dart';
import '../../application/presentation_lunch.dart';
import '../../../biosignal/data/heart_repository.dart';
import '../../../guardian/application/guardians_provider.dart';
import '../../../guardian/data/guardian_repository.dart';
import '../../../biosignal/application/heart_device.dart';
import '../../../biosignal/presentation/screens/polar_screen.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../reminder/application/alarm_preferences.dart';
import '../../../reminder/application/reminder_notifications.dart';
import '../../../reminder/presentation/screens/alarm_settings_screen.dart';
import '../../../medication/domain/medication_models.dart';
import '../../../medication/presentation/widgets/dose_flow_sheets.dart';
import '../../../easy_flow/domain/easy_flow.dart';
import '../../../medication/presentation/widgets/dose_guard_sheets.dart';
import '../../../profile/application/current_user_controller.dart';
import 'package:go_router/go_router.dart';
import '../../../medicines/application/family_medicine_inbox.dart';
import '../../../medicines/application/user_medicines_controller.dart';
import '../../../medicines/domain/display_policy.dart';

/// 12 / 15 · 오늘 · 홈.
///
/// **주인공은 "지금 드실 약" 하나.** 나머지는 아래로 밀린다.
class PatientHomeScreen extends ConsumerStatefulWidget {
  /// 기록 탭으로 이동.
  final VoidCallback? onOpenRecord;

  /// 심박수 관리 화면으로 이동.
  final VoidCallback? onOpenHeartbeat;

  /// 약 목록 · AI 약사 · 처방전 넣기로 이동.
  final VoidCallback? onOpenMedicines;
  final VoidCallback? onOpenChat;
  final VoidCallback? onOpenPrescription;

  /// 약 하나를 눌렀을 때 설명 화면으로.
  final void Function(Medicine medicine)? onOpenDrug;

  /// "먹었어요" 뒤 심박수를 재러 갈 때. 방금 기록한 시간대를 함께 넘긴다.
  /// 다 재면 재는 단추를 거둔다. 그냥 나오면 단추는 홈에 남는다.
  final Future<int?> Function(DoseSlot slot)? onMeasure;

  /// 약을 들기 **전에** 재러 갈 때. 다 재면 잰 값을 돌려준다.
  /// 기기를 쓰는 분에게만 쓰인다.
  final Future<int?> Function(DoseSlot slot)? onMeasureBefore;

  /// 복약을 기록한 뒤 완료 화면으로. 방금 기록한 시간대를 함께 넘긴다.
  final void Function(DoseSlot slot)? onDone;

  /// 쉬운 모드인지. 헤더의 아바타가 "메뉴" 버튼으로 바뀌고
  /// 스크롤 아래 여백이 하단 바만큼 늘어난다.
  final bool easyMode;

  /// 쉬운 모드에서 메뉴를 열 때.

  const PatientHomeScreen({
    super.key,
    this.onOpenRecord,
    this.onOpenHeartbeat,
    this.onOpenMedicines,
    this.onOpenChat,
    this.onOpenPrescription,
    this.onOpenDrug,
    this.onMeasure,
    this.onMeasureBefore,
    this.onDone,
    this.easyMode = false,
  });

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  // 도움말이 동그라미를 칠 자리들. 화면에 없으면 그 걸음은 건너뛴다.
  final _emptyKey = GlobalKey();
  final _slotsKey = GlobalKey();
  final _bigButtonKey = GlobalKey();
  final _stepsKey = GlobalKey();
  final _alarmTileKey = GlobalKey();
  final _sensorTileKey = GlobalKey();

  /// 홈 화면을 하나씩 짚어 가며 설명한다.
  void _openHelp() {
    final usesDevice = ref.read(heartDevicePairedProvider);
    CoachMarks.show(context, [
      // 약이 없을 때만 그려지는 칸이다. 약이 들어오면 이 걸음은 저절로
      // 건너뛴다 — 처음 쓰시는 분께 가장 먼저 할 말이 이것이다.
      CoachMark(
        target: _emptyKey,
        title: '처방전 등록',
        body:
            '처방전을 등록하면 오늘 드실 약과 복용 시간이 이 화면에 나옵니다. '
            '사진으로 찍거나 손으로 적어 넣을 수 있습니다.',
        boxed: true,
        radius: 22,
      ),
      CoachMark(
        target: _slotsKey,
        title: '복용 시간대 선택',
        body:
            '복용할 시간대를 선택하세요. 정해진 시간과 다른 때에 복용하더라도 '
            '선택한 시간대로 기록됩니다.',
        boxed: true,
        radius: 22,
      ),
      if (usesDevice)
        CoachMark(
          target: _stepsKey,
          title: '심박수 측정 단계',
          body:
              '센서가 연결되어 있으면 복용 전과 복용 후에 각각 심박수를 '
              '측정합니다. 현재 단계가 파란색으로 표시됩니다.',
          boxed: true,
          radius: 18,
        ),
      CoachMark(
        target: _bigButtonKey,
        title: '복용 완료 버튼',
        body:
            '약을 복용한 뒤 누르면 누른 시각으로 복용이 기록됩니다. 잘못 '
            '눌렀다면 같은 버튼이 "취소하기"로 바뀌어 기록을 취소할 수 있습니다.',
        // 테가 뛸 때 1.09배까지 커진다. 그만큼 둘레를 더 밝혀 둔다.
        padding: 16,
      ),
      CoachMark(
        target: _alarmTileKey,
        title: '알람',
        body: '다음 복약 알람 시각입니다. 누르면 알람 시각을 변경할 수 있습니다.',
        boxed: true,
        radius: 18,
      ),
      CoachMark(
        target: _sensorTileKey,
        title: usesDevice ? '기기 연결 해제' : '센서 연결',
        body: usesDevice
            ? '연결된 심박 센서의 연결을 해제합니다.'
            : '심박 센서를 연결합니다. 연결하면 복용 전후로 심박수를 측정할 수 있습니다.',
        boxed: true,
        radius: 18,
      ),
    ]);
  }

  /// 방금 기록한 시간대. 파란 띠로 알리고, X를 누르면 사라진다.
  DoseSlot? _recordedSlot;

  /// 직접 고르신 때. 아침을 늦게 드셔도 그 때로 적힐 수 있게 한다.
  /// 안 고르셨으면 아직 안 드신 가장 이른 때를 따른다.
  DoseSlot? _pickedSlot;

  /// 드신 뒤 아직 안 재다 남은 시간대. 측정 화면을 닫고 나와도
  /// 홈에 재는 길이 남아 있어야 한다.
  DoseSlot? _measureAfterSlot;

  /// 때마다 먹기 전에 잰 심박수. 다음 때로 넘어가면 그 때에는 값이 없어
  /// 다시 1단계부터 시작한다.
  final Map<DoseSlot, int> _beforeBpm = {
    // 화면 확인용 가짜 데이터에서는 먹기 전 값을 미리 넣어 둔다.
    // 재는 걸음부터 거치지 않고 다음 화면을 바로 볼 수 있다.
    if (mockBeforeBpm() != null)
      for (final slot in DoseSlot.values) slot: mockBeforeBpm()!,
  };

  @override
  void initState() {
    super.initState();
    unawaited(_restorePresentationLunch());
    // 잔여일이 0이면 홈에 들어오는 순간 리필 시트를 연다. 하루 한 번만.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskRefill());
    // 가족이 대신 넣어 준 약이 있으면 홈에 들어서자마자 알린다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTellArrived());
    // 보호자가 함께 보기를 청했으면 수락할지 물어본다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskGuardian());
    ReminderNotifications.pendingAction.addListener(_onNotificationAction);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _onNotificationAction(),
    );
  }

  Future<void> _restorePresentationLunch() async {
    final id = MvpSession.userId;
    final now = DateTime.now();
    if (!PresentationHistory.applies(id) ||
        now.year != 2026 ||
        now.month != 10 ||
        now.day != 6) {
      return;
    }
    final data = await HeartRepository().fetch(userId: id);
    if (!mounted || MvpSession.userId != id || data == null) return;
    final bpm = presentationLunchBeforeBpm(id, DateTime.now(), data.readings);
    if (bpm == null || _beforeBpm.containsKey(DoseSlot.lunch)) return;
    setState(() => _beforeBpm[DoseSlot.lunch] = bpm);
  }

  @override
  void dispose() {
    ReminderNotifications.pendingAction.removeListener(_onNotificationAction);
    super.dispose();
  }

  /// 잠금화면 알림에서 누른 단추를 여기서 마무리한다 (프로토타입 40번).
  void _onNotificationAction() {
    final action = ReminderNotifications.pendingAction.value;
    if (action == null || !mounted) return;
    ReminderNotifications.pendingAction.value = null;
    final next = ref.read(medicationProvider).nextDose;
    if (next == null) return;
    if (action == ReminderNotifications.takeActionId) {
      unawaited(_take(next.slot));
    } else if (action == ReminderNotifications.snoozeActionId) {
      _snooze(next.slot);
    }
  }

  /// 이번에 띄운 연결 요청. 같은 요청을 다시 묻지 않는다.
  final Set<String> _askedLinks = <String>{};

  /// 보호자가 청한 연결을 홈에서 한 번 물어본다.
  ///
  /// 내가 수락해야 열린다 — 묻지 않고 더해 두면 누가 내 약을 보는지
  /// 모른 채 열리게 된다.
  Future<void> _maybeAskGuardian() async {
    if (!mounted) return;
    // 못 읽으면 묻지 않는다. 연결 요청은 다음에 들어올 때 다시 본다.
    final List<GuardianContact> guardians;
    try {
      guardians = await ref.read(guardiansProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final waiting = guardians.where((g) => g.awaitsMyAnswer).toList();
    if (waiting.isEmpty) return;
    final invite = waiting.first;
    if (!_askedLinks.add(invite.id)) return;

    final accept = await showSeniorYesNoDialog(
      context: context,
      title: '${invite.label} 님이\n함께 보기를 청했어요',
      message:
          '수락하면 약 드신 것과 심박수를 함께 봅니다. '
          '나중에 내 정보 → 가족에서 끊을 수 있어요.',
      yesLabel: '네, 함께 볼게요',
      noLabel: '아니요',
    );
    if (!mounted) return;

    final repository = GuardianRepository();
    try {
      if (accept) {
        await repository.accept(invite.id);
      } else {
        await repository.remove(invite.id);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      showSeniorSnackbar(context, error.message, error: true);
      return;
    }
    if (!mounted) return;
    ref.invalidate(guardiansProvider);
    unawaited(ref.read(medicationProvider.notifier).refreshFromServer());
    showSeniorSnackbar(
      context,
      accept
          ? '${invite.name} 님이 이제 함께 볼 수 있어요'
          : '${invite.name} 님의 요청을 거절했어요',
    );
  }

  /// 홈 알림 칸에 적을 말. 다음에 울릴 시각을 "다음 알람 18:00"처럼
  /// 적는다 — 시각만 적으면 무슨 시각인지 알 길이 없다.
  static String _nextAlarmLabel(
    AlarmPreferences alarm, {
    required bool hasDoses,
  }) {
    // 넣은 약이 없으면 울릴 알람도 없다. 시각을 적어 두면 그 시각에
    // 소리가 날 것으로 믿고 기다리시게 된다.
    if (!hasDoses) return '알람 없음';
    final times = alarm.ringingTimes;
    if (!alarm.autoAlarm || times.isEmpty) return '알림 꺼짐';
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    // 오늘 남은 것 중 첫 번째, 없으면 내일 첫 번째.
    final next = times.firstWhere(
      (t) => t > minutes,
      orElse: () => times.first,
    );
    return '다음 알람 ${AlarmPreferences.clock(next)}';
  }

  /// "알림 시간" 칸 — 소리로 울릴 시각을 고치러 간다.
  Future<void> _openAlarmSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AlarmSettingsScreen()),
    );
  }

  /// 심박기기 연결로. 지금까지는 기록 › 오늘 심박수 › 기기 연결로
  /// 세 걸음 들어가야 닿았다. 홈에서 한 번에 가게 둔다.
  Future<void> _openHeartDevice() async {
    // 가짜 데이터로 볼 때는 기기가 없다. 연결된 셈 치고 화면만
    // 바뀜다 — 보여 주려는 것은 펜어림이 아니라 그 뒤의 홈이다.
    if (mockData) {
      await ref.read(heartDevicePairedProvider.notifier).set(true);
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PolarScreen()));
  }

  /// 센서 연결을 끊는다. 표시만 바꾸지 않고 실제로 끊는다 —
  /// 폴라 화면의 "연결 끊기"와 같은 일을 한다.
  Future<void> _disconnectHeartDevice() async {
    if (!mockData) await ref.read(heartSensorProvider).stop();
    await ref.read(heartDevicePairedProvider.notifier).set(false);
    if (!mounted) return;
    setState(() => _measureAfterSlot = null);
    showSeniorSnackbar(context, '센서 연결을 끊었어요');
  }

  /// 장부에 없는 약 — 내가 넣지 않았는데 들어와 있는 약을 알린다.
  ///
  /// 내가 등록한 약은 등록하는 자리에서 미리 장부에 적으므로 여기 걸리지
  /// 않는다. 처음 켠 기기는 장부가 비어 있어 전부 적어 두고 넘어간다 —
  /// 쓰던 약을 "방금 들어왔다"고 알리면 안 되기 때문이다.
  Future<void> _maybeTellArrived() async {
    if (!mounted) return;
    final userId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
    if (userId.isEmpty) return;
    final medicines = ref.read(userMedicinesProvider).valueOrNull;
    if (medicines == null || medicines.isEmpty) return;

    final arrived = await FamilyMedicineInbox.unseen(
      userId,
      medicines.map((m) => m.medicineCode),
    );
    if (!mounted || arrived.isEmpty) return;

    final rows = [
      for (final medicine in medicines)
        if (arrived.contains(medicine.medicineCode))
          {
            'name': nameWithoutStrength(medicine.displayName),
            'dose': medicine.amount,
          },
    ];
    if (rows.isEmpty) return;

    // 누가 넣었는지는 서버가 알려주지 않는다. "가족"까지만 말한다.
    unawaited(FamilyMedicineInbox.markSeen(userId, arrived));
    if (!mounted) return;
    context.push('/medicine-arrived', extra: {'medicines': rows});
  }

  Future<void> _maybeAskRefill() async {
    // 첫 프레임 뒤에 불린다. 그 사이 화면이 닫혔으면 ref를 만지면 안 된다.
    if (!mounted) return;
    final controller = ref.read(medicationProvider.notifier);
    if (!controller.shouldAskRefill) return;
    controller.markRefillAsked();

    final today = ref.read(medicationProvider);
    final startedOn = today.courseStartedOn!;
    final choice = await showRefillSheet(
      context,
      startedOn: '${startedOn.month}월 ${startedOn.day}일',
      totalDays: today.courseTotalDays!,
    );
    if (!mounted) return;
    switch (choice) {
      case RefillChoice.addPrescription:
        widget.onOpenPrescription?.call();
      case RefillChoice.tellFamily:
        showSeniorSnackbar(
          context,
          '${ref.read(medicationProvider).guardianTitle}에게 알렸어요',
        );
      case RefillChoice.askTomorrow:
        break;
    }
  }

  /// "먹었어요" — 바로 기록한다.
  ///
  /// 센서를 차고 계신지 묻지 않는다. 기기를 쓰는 분인지는 앱이 이미 알고,
  /// 모르는 것을 물어 흐름을 끊을 이유가 없다.
  Future<void> _take(DoseSlot slot) async {
    final controller = ref.read(medicationProvider.notifier);

    // 이미 기록된 시간대는 묻기 전에 막는다. 사후 안내가 아니라 사전 차단이다.
    if (ref.read(medicationProvider).doseOf(slot).taken) {
      await _showDuplicateGuard(slot);
      return;
    }

    final outcome = await controller.take(slot);
    if (!mounted) return;

    switch (outcome) {
      case DoseCheckOutcome.alreadyTaken:
        await _showDuplicateGuard(slot);
      case DoseCheckOutcome.tooLate:
        final proceed = await showLateDoseSheet(context: context, slot: slot);
        if (proceed && mounted) {
          await controller.takeAnyway(slot);
          if (!mounted) return;
          _afterRecord(slot);
        }
      case DoseCheckOutcome.recorded:
        _afterRecord(slot);
    }
  }

  void _afterRecord(DoseSlot slot) {
    // 기록하고 나서도 오늘 화면에 남는다. 화면이 바뀌면 방금 무엇을
    // 눌렀는지 놓친다. 대신 맨 위에 파란 띠로 알린다.
    setState(() {
      _recordedSlot = slot;
      // 다음 할 일로 저절로 옮긴다.
      _pickedSlot = null;
    });
    // 기기를 쓰는 분은 드신 뒤에 한 번 더 잰다. 다만 화면을 가로채지
    // 않는다 — 가운데 단추가 "심박수 측정"으로 바뀌고, 그걸 누르면 잰다.
    if (ref.read(heartDevicePairedProvider)) {
      setState(() => _measureAfterSlot = slot);
    } else {
      widget.onDone?.call(slot);
    }
  }

  /// 드신 뒤 재러 간다. 다 재고 돌아오면 홈에서 그 단추를 거둔다.
  Future<void> _measureAfter(DoseSlot slot) async {
    final bpm = await widget.onMeasure?.call(slot);
    if (!mounted || bpm == null) return;
    setState(() => _measureAfterSlot = null);
  }

  /// 먹기 전 심박수를 재러 간다. 다 재면 그 값이 `_beforeBpm`에 남는다.
  Future<void> _measureBefore(DoseSlot slot) async {
    final bpm = await widget.onMeasureBefore?.call(slot);
    if (!mounted || bpm == null) return;
    setState(() => _beforeBpm[slot] = bpm);
  }

  Future<void> _showDuplicateGuard(DoseSlot slot) async {
    final dose = ref.read(medicationProvider).doseOf(slot);
    await showDuplicateDoseSheet(
      context: context,
      dose: dose,
      onUndo: () => ref.read(medicationProvider.notifier).undo(slot),
    );
  }

  void _undo(DoseSlot slot) {
    ref.read(medicationProvider.notifier).undo(slot);
    setState(() => _recordedSlot = null);
  }

  void _snooze(DoseSlot slot) {
    final until = ref.read(medicationProvider.notifier).snooze(slot);
    if (!mounted) return;
    showSeniorSnackbar(context, '${DoseSlot.absoluteTime(until)}에 다시 알려드려요');
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(medicationProvider);
    final next = today.nextDose;
    final now = DateTime.now();
    final remaining = today.doses.where((dose) => !dose.taken).length;
    // 기기를 쓰는 분인지에 따라 홈이 통째로 다른 흐름이 된다.
    final usesDevice = ref.watch(heartDevicePairedProvider);
    // 드신 뒤 재기가 남았으면 그것이 지금 할 일이다.
    final afterSlot = usesDevice ? _measureAfterSlot : null;
    // 고르신 때가 있으면 그 때를, 없으면 아직 안 드신 가장 이른 때를
    // 지금 할 일로 삼는다. 늦게 드셔도 아침은 아침으로 적힐 수 있어야 한다.
    final pickedSlot = _pickedSlot ?? next?.slot;
    final pickedDose = pickedSlot == null
        ? null
        : today.doses.where((dose) => dose.slot == pickedSlot).firstOrNull;
    // 고른 때를 이미 드셨으면 단추는 되돌리기가 된다.
    final pickedTaken = pickedDose?.taken ?? true;
    // 센서를 쓸 때는 위에 걸음 칸이 하나 더 붙는다. 동그라미가 줄어들지
    // 않게 위아래 여백을 거둔다.
    final tight = usesDevice && (!pickedTaken || afterSlot != null);
    final gap = tight ? 10.0 : 20.0;

    return Container(
      color: AppColors.pageBg,
      child: Column(
        children: [
          // 간편 화면에서는 쉘이 위에 걸음 표시와 "일반 화면으로"를 둔다.
          // 여기서 또 머리를 그리면 두 줄이 겹친다.
          if (!widget.easyMode)
            HomeTopBar(
              userName: ref.watch(currentUserNameProvider),
              onHelp: _openHelp,
              date: now,
              easyMode: widget.easyMode,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final bottomPad = widget.easyMode
                    ? kEasyBarScrollPadding
                    : 28.0;
                // 동그라미는 남는 자리를 다 쓴다. 제목·칩·타일이 차지하는
                // 만큼을 빼고 남은 높이와 화면 너비 중 작은 쪽에 맞춘다.
                // 글자를 키우면 그 셋도 함께 커지므로 배율을 태워 잰다.
                // 글자를 키우면 한 화면에 다 못 담는다. 그때만 스크롤로
                // 넘기고, 보통 크기에서는 남는 자리에 딱 맞춰 채운다.
                // 작은 화면이나 키운 글씨에서는 한 화면에 다 못 담는다.
                // 그때만 스크롤로 넘긴다.
                final scrolls =
                    MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                    box.maxHeight < 560;
                final body = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (today.doses.isEmpty)
                      SeniorCard(
                        key: _emptyKey,
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          children: [
                            // 못 불러온 것을 "약이 없어요"로 말하지 않는다.
                            Text(switch (today.fetchStatus) {
                              MedicationFetchStatus.loading =>
                                '오늘 약을 불러오는 중이에요',
                              MedicationFetchStatus.failed => '오늘 약을 불러오지 못했어요',
                              MedicationFetchStatus.ready => '등록된 약이 없어요',
                            }, style: AppText.cardTitle(size: 22)),
                            const SizedBox(height: 8),
                            Text(
                              switch (today.fetchStatus) {
                                MedicationFetchStatus.loading => '잠시만 기다려 주세요.',
                                MedicationFetchStatus.failed =>
                                  '인터넷 연결을 확인하고 다시 시도해 주세요.',
                                MedicationFetchStatus.ready =>
                                  '처방전 사진을 찍으면 오늘 먹을 약을 알려드려요.',
                              },
                              textAlign: TextAlign.center,
                              style: AppText.body(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (today.fetchStatus !=
                                MedicationFetchStatus.loading) ...[
                              const SizedBox(height: 14),
                              SeniorButton(
                                label:
                                    today.fetchStatus ==
                                        MedicationFetchStatus.failed
                                    ? '다시 시도'
                                    : '처방전 등록하기',
                                onPressed:
                                    today.fetchStatus ==
                                        MedicationFetchStatus.failed
                                    ? () => ref
                                          .read(medicationProvider.notifier)
                                          .refreshFromServer()
                                    : widget.onOpenPrescription,
                              ),
                            ],
                          ],
                        ),
                      )
                    else ...[
                      // 오늘 할 일을 한 줄로 먼저 말한다.
                      _TodayHeadline(remaining: remaining),
                      const SizedBox(height: 18),
                      _SlotChips(
                        key: _slotsKey,
                        today: today,
                        picked: pickedSlot,
                        onPick: (slot) => setState(() => _pickedSlot = slot),
                      ),
                      const SizedBox(height: 8),
                      // 누를 수 있다는 것을 모르면 평생 못 누른다. 한 줄만 적는다.
                      Text(
                        '어느 때 약인지 고르고 복용 완료를 누르세요',
                        textAlign: TextAlign.left,
                        style: AppText.caption(size: 16),
                      ),
                      // 기기를 연결하면 걸음 칸이 위에서 자라난다. 그만큼
                      // 아래 동그라미가 줄며 내려가 무엇이 바뀜는지 눈으로 따라간다.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: usesDevice && (!pickedTaken || afterSlot != null)
                            ? Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: _HeartSteps(
                                  key: _stepsKey,
                                  beforeBpm:
                                      _beforeBpm[afterSlot ?? pickedSlot],
                                  afterPending: afterSlot != null,
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      SizedBox(height: gap),
                      // 남는 세로 자리를 그대로 받아 그 안에 맞춘다.
                      _Fill(
                        scrolls: scrolls,
                        child: _BigDoseButton(
                          focusKey: _bigButtonKey,
                          done: pickedTaken,
                          // 기기를 쓰는 분은 먹기 전에 먼저 잰다.
                          measureFirst:
                              !pickedTaken &&
                              usesDevice &&
                              _beforeBpm[pickedSlot] == null,
                          // 드신 뒤 한 번 더 — 같은 단추로 같은 말을 한다.
                          measureAfter: afterSlot != null,
                          onMeasureAfter: afterSlot == null
                              ? null
                              : () => _measureAfter(afterSlot),
                          onSkipMeasure: afterSlot == null
                              ? null
                              : () => setState(() => _measureAfterSlot = null),
                          compact:
                              usesDevice && (!pickedTaken || afterSlot != null),
                          onMeasure: pickedTaken || pickedSlot == null
                              ? null
                              : () => _measureBefore(pickedSlot),
                          onTake: pickedTaken || pickedSlot == null
                              ? null
                              : () => _take(pickedSlot),
                          onUndo: !pickedTaken
                              ? null
                              : () => _undo(
                                  pickedSlot ??
                                      _recordedSlot ??
                                      today.doses.last.slot,
                                ),
                        ),
                      ),
                    ],
                    // 알람과 센서는 약이 없어도 쓸 수 있다. 등록을 기다리게
                    // 할 까닭이 없으므로 빈 화면에서도 자리를 지킨다.
                    // 위아래 여백을 같게 둔다. 두 칸 정가운데에 단추가 온다.
                    SizedBox(height: gap),
                    _HomeTiles(
                      alarmKey: _alarmTileKey,
                      sensorKey: _sensorTileKey,
                      alarmLabel: _nextAlarmLabel(
                        ref.watch(alarmPreferencesProvider),
                        hasDoses: today.doses.isNotEmpty,
                      ),
                      onOpenAlarm: _openAlarmSettings,
                      // 아직 기기를 안 쓰시는 분께는 연결 길을 먼저
                      // 보여 드린다. 약 보기는 아래 “내 약” 칸에도 있다.
                      onConnectDevice: usesDevice ? null : _openHeartDevice,
                      onDisconnectDevice: usesDevice
                          ? _disconnectHeartDevice
                          : null,
                      onOpenMedicines: widget.onOpenMedicines,
                    ),
                    if (today.daysLeft != null) ...[
                      const SizedBox(height: 16),
                      _RefillRow(daysLeft: today.daysLeft!),
                    ],
                  ],
                );
                return Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPad),
                  child: scrolls ? SingleChildScrollView(child: body) : body,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "오늘 드실 약이 1번 남았어요" — 다 드셨으면 "오늘 약을 다 드셨어요".
class _TodayHeadline extends StatelessWidget {
  final int remaining;

  const _TodayHeadline({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final style = AppText.screenTitle(size: 28);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
      child: remaining == 0
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '오늘 약을 ',
                    style: style.copyWith(fontWeight: FontWeight.w500),
                  ),
                  TextSpan(text: '다 드셨어요', style: style),
                ],
              ),
            )
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '오늘 드실 약이 ',
                    style: style.copyWith(fontWeight: FontWeight.w500),
                  ),
                  TextSpan(text: '$remaining번 남았어요', style: style),
                ],
              ),
            ),
    );
  }
}

/// 아침·점심·저녁 세 칸. 누르면 그 때를 고른다.
///
/// 고른 때는 파란 칩, 드신 때는 흰 칩에 체크와 드신 시각, 약이 없는 때는
/// 회색 칩에 "없음"이다.
///
/// 몇 시에 드시는지는 미리 정해 두지 않는다. 아침을 오후 네 시에 드셔도 그
/// 시각이 그대로 적힐 뿐이다. 소리로 울리는 시각은 알림에서 따로 고른다.
class _SlotChips extends StatelessWidget {
  final TodayMedication today;

  /// 지금 고른 때. 여기에 대고 "먹었어요"를 누른다.
  final DoseSlot? picked;

  /// 칸을 눌렀을 때.
  final ValueChanged<DoseSlot> onPick;

  const _SlotChips({
    super.key,
    required this.today,
    required this.picked,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final slot in DoseSlot.values) ...[
          Expanded(child: _chip(slot)),
          if (slot != DoseSlot.values.last) const SizedBox(width: 12),
        ],
      ],
    );
  }

  /// 드신 시각 — "16:00". 아직 안 드셨으면 빈 문자열이다.
  static String _clock(DateTime? at) {
    if (at == null) return '';
    final hour = at.hour.toString().padLeft(2, '0');
    final minute = at.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _chip(DoseSlot slot) {
    final dose = today.doses.where((d) => d.slot == slot).firstOrNull;
    final isPicked = picked == slot;
    final taken = dose?.taken ?? false;
    final clock = _clock(dose?.takenAt);

    final under = dose == null
        ? '없음'
        : taken
        ? (clock.isEmpty ? '드셨어요' : clock)
        : '미복용';
    final background = dose == null
        ? AppColors.neutralFill
        : isPicked
        ? AppColors.pointFill
        : AppColors.surface;
    final foreground = dose == null
        ? AppColors.textSecondary
        : isPicked
        ? Colors.white
        : AppColors.point;
    // 아래 줄(미복용·드신 시각)은 검정으로 둔다. 위 이름까지 파랑이면
    // 칸 전체가 한 덩어리로 보여 상태가 눈에 들어오지 않는다.
    final underColor = dose != null && !isPicked
        ? AppColors.textPrimary
        : foreground;

    return Semantics(
      button: dose != null,
      selected: isPicked,
      label: dose == null
          ? '${slot.label} 약 없음'
          : taken
          ? '${slot.label} $under에 드셨어요, 누르면 고릅니다'
          : '${slot.label} 아직 안 드셨어요, 누르면 고릅니다',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: dose == null ? null : () => onPick(slot),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 64),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(30),
                  // 흰 칩만 그림자로 띄운다. 채운 칩은 색이 이미 자리를 잡는다.
                  boxShadow: background == AppColors.surface
                      ? kCardShadow
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      slot.label,
                      textAlign: TextAlign.center,
                      style: AppText.cardTitle(size: 19, color: foreground),
                    ),
                    Text(
                      under,
                      textAlign: TextAlign.center,
                      style: AppText.cardTitle(size: 16, color: underColor),
                    ),
                  ],
                ),
              ),
              // 드신 때는 칩 왼쪽 위에 동그란 체크를 붙인다. 글자 줄에
              // 끼우면 "아침"이 옆으로 밀려 자리가 좁아진다.
              if (taken)
                Positioned(
                  left: -2,
                  top: -2,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.pointFill,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.pageBg, width: 2),
                    ),
                    child: const Icon(
                      TablerIcons.check,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 남는 세로 자리를 차지하는 껍데기. 스크롤하는 화면에서는 아무것도
/// 하지 않는다 — 스크롤 안에서는 "남는 자리"라는 것이 없다.
class _Fill extends StatelessWidget {
  final bool scrolls;
  final Widget child;

  const _Fill({required this.scrolls, required this.child});

  @override
  Widget build(BuildContext context) =>
      scrolls ? child : Expanded(child: child);
}

/// 기기를 쓰는 분의 세 걸음 — 먹기 전 재기 · 먹었어요 · 먹은 뒤 재기.
///
/// 지금 어디쯤인지 번호로 말한다. 끝난 걸음은 체크로 바뀌고, 먹기 전 재기가
/// 끝나면 라벨이 잰 값으로 바뀐다 — 쟀다는 사실보다 얼마였는지가 궁금하다.
class _HeartSteps extends StatelessWidget {
  /// 먹기 전에 잰 값. 아직 안 쟀으면 null이다.
  final int? beforeBpm;

  /// 드신 뒤 재기가 남은 상태. 세 번째 걸음을 가리킨다.
  final bool afterPending;

  const _HeartSteps({
    super.key,
    required this.beforeBpm,
    this.afterPending = false,
  });

  @override
  Widget build(BuildContext context) {
    final done = beforeBpm != null;
    final current = afterPending
        ? 2
        : done
        ? 1
        : 0;
    final labels = [done ? '먹기 전 $beforeBpm회' : '먹기 전 측정', '복용 완료', '먹은 뒤 측정'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: kCardShadow,
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: _step(index: i, current: current, label: labels[i]),
            ),
        ],
      ),
    );
  }

  Widget _step({
    required int index,
    required int current,
    required String label,
  }) {
    final passed = index < current;
    final now = index == current;
    return Semantics(
      label: passed
          ? '$label, 끝났어요'
          : now
          ? '$label, 지금 할 차례'
          : label,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: passed
                    ? AppColors.pointTint
                    : now
                    ? AppColors.pointFill
                    : AppColors.secondaryFill,
                shape: BoxShape.circle,
              ),
              child: passed
                  ? const Icon(
                      TablerIcons.check,
                      size: 16,
                      color: AppColors.point,
                    )
                  : Text(
                      '${index + 1}',
                      style: AppText.cardTitle(
                        size: 15,
                        color: now ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.cardTitle(
                size: 16,
                color: now ? AppColors.textPrimary : AppColors.textSecondary,
                weight: now ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 오늘 화면에서 제일 큰 것 하나. 드시기 전에는 파란 "먹었어요",
/// 다 드신 뒤에는 흰 "취소하기"로 바뀐다.
///
/// 바깥의 연한 테는 심장이 뛰듯 두 번씩 커졌다 줄며 눈을 끈다.
/// 어르신이 이 화면에서 누를 것이 하나뿐임을 몸으로 알리는 장치다.
class _BigDoseButton extends StatefulWidget {
  final bool done;

  /// 약을 들기 전에 심박수부터 재야 하는 상태.
  /// 기기를 쓰는 분이 아직 안 쟀을 때다.
  final bool measureFirst;

  /// 위에 걸음 표시가 붙어 자리가 좁은 상태. 동그라미를 한 치수 줄인다.
  final bool compact;

  /// 드신 뒤 재기가 남은 상태. 먼저 재던 때와 같은 단추를 둔다.
  final bool measureAfter;
  final VoidCallback? onMeasureAfter;

  /// 지금은 재지 않겠다고 할 때. 단추 아래 작은 글자로 둔다.
  final VoidCallback? onSkipMeasure;
  final VoidCallback? onMeasure;
  final VoidCallback? onTake;
  final VoidCallback? onUndo;

  /// 도움말이 짚을 자리. 뛰는 둘레 테까지 감싸는 자리에 단다 — 단추
  /// 자리 전체를 짚으면 위아래 칸까지 덮고, 진한 동그라미만 짚으면
  /// 뛰는 테가 그늘 밖으로 삐져나온다.
  final GlobalKey? focusKey;

  const _BigDoseButton({
    this.focusKey,
    required this.done,
    this.measureFirst = false,
    this.measureAfter = false,
    this.onMeasureAfter,
    this.onSkipMeasure,
    this.compact = false,
    this.onMeasure,
    this.onTake,
    this.onUndo,
  });

  @override
  State<_BigDoseButton> createState() => _BigDoseButtonState();
}

class _BigDoseButtonState extends State<_BigDoseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  /// 쿵-쿵 하고 두 번 뛴 뒤 쉰다. 한 번만 뛰면 기계가 깜빡이는 것 같고,
  /// 쉬는 참이 없으면 화면이 계속 흔들려 글자를 읽기 어렵다.
  late final Animation<double> _pulse = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.05,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 10,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.05,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 10,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.09,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 12,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.09,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 16,
    ),
    TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 52),
  ]).animate(_beat);

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  /// 받은 자리보다 조금 크게 그린다. 높이가 끝없는 자리(글씨를 키워
  /// 스크롤로 넘기는 때)에서는 그냥 두고 그린다.
  Widget _room(bool bounded, double height, Widget child) => bounded
      ? OverflowBox(
          maxHeight: height,
          alignment: Alignment.center,
          child: child,
        )
      : child;

  @override
  Widget build(BuildContext context) {
    final measuring =
        widget.measureAfter || (widget.measureFirst && !widget.done);
    final label = measuring
        ? '심박수 측정'
        : widget.done
        ? '취소하기'
        : '복용 완료';
    // 재는 단추는 작은 설명 줄 대신 두 줄로 크게 적는다. 먼저 재는
    // 때나 드신 뒤에 재는 때나 같은 말로 말한다.
    final lines = measuring ? const ['심박수', '측정'] : [label];
    final quiet = widget.done && !measuring;
    final fill = quiet ? AppColors.surface : AppColors.pointFill;
    final ink = quiet ? AppColors.textPrimary : Colors.white;
    // 움직임을 꺼 둔 기기에서는 뛰지 않는다. 다 드신 뒤에도 멈춘다 —
    // 누를 것이 없는데 눈을 끌 이유가 없다.
    final beating = !quiet && !MediaQuery.disableAnimationsOf(context);
    if (beating) {
      if (!_beat.isAnimating) _beat.repeat();
    } else if (_beat.isAnimating) {
      _beat.stop();
      _beat.value = 0;
    }

    // 위에 걸음 칸이 붙고 떨어질 때 지름이 한 꺼번에 바뀜지 않게
    // 최대 치수를 천천히 옮긴다. 칸이 자라나는 만큼 동그라미가 줄며
    // 아래로 내려간다.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: widget.compact ? 252.0 : 300.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, cap, _) => LayoutBuilder(
        builder: (context, box) {
          // 받은 자리 안에 테까지 들어가야 한다. 가로·세로 중 좁은 쪽에
          // 맞추되, 글자를 읽을 수 있는 크기 아래로는 줄이지 않는다.
          // 가로는 양옆을 한 뼘씩 비워 둔다. 화면 폭을 꽉 채우면
          // 동그라미가 벽에 낀 것처럼 답답해 보인다.
          // 건너뛰는 줄이 붙으면 그만큼 동그라미 자리가 줄어든다.
          // 건너뛰는 글자는 원 옆에 서므로 원 크기를 건드리지 않는다.
          const skipRoom = 0.0;
          // 걸음 칸이 붙어 자리가 좁을 때는 받은 자리보다 조금 더 크게
          // 잡는다. 넣는 동그라미는 그 안에 있고, 말가의 연한 테만
          // 위아래 칸에 살짝 걸친다.
          final stretch = widget.compact ? 16.0 : 0.0;
          final room = math.min(
            (box.maxWidth.isFinite ? box.maxWidth : 320) - 56,
            (box.maxHeight.isFinite ? box.maxHeight : 320) + stretch - skipRoom,
          );
          // 걸음 표시가 위에 붙으면 자리가 좁다. 그때는 한 치수 줄인다.
          // 읽힐 크기(180) 아래로는 줄이지 않으되, 받은 자리가 그보다
          // 좁으면 그 자리에 맞춘다 — 칸이 자라나는 찰나에 비지 않게.
          final floor = math.min(180.0, math.max(room, 0.0));
          final outer = room.clamp(floor, cap).toDouble();
          // 가운데 단추 크기는 그대로 두고, 둘레 테만 넓게 편다. 위 칸과
          // 겹쳐도 비치는 색이라 칸과 테가 함께 보인다.
          final size = outer * 0.78;
          // 쉬고 있을 때는 단추보다 조금만 크다. 뛸 때(최대 1.09배) 커지는
          // 만큼만 여유를 둔다.
          final halo = size * 1.2;
          // 글자와 아이콘은 지름을 따라간다. 동그라미만 커지고 글자가
          // 그대로면 가운데가 비어 보인다.
          final labelSize = (size * 0.135).clamp(24.0, 34.0).toDouble();
          final iconSize = (size * 0.24).clamp(44.0, 66.0).toDouble();
          final labelStyle = AppText.cardTitle(size: labelSize, color: ink);
          // 건너뛰는 글자는 테 오른쪽에 세우되, 받은 자리를 넘어가면
          // 넘어간 쪽이 눌리지 않는다. 글자 너비를 재어 자리 안에 눕힌다.
          final regionW = box.maxWidth.isFinite ? box.maxWidth : 320.0;
          final skipW = _skipWidth(context);
          final skipLeft = math.max(
            0.0,
            math.min(regionW / 2 + halo / 2 + 2, regionW - skipW),
          );

          // 위 칸과 아래 칸 사이 정가운데에 둔다.
          return Align(
            alignment: Alignment.center,
            child: _room(
              box.maxHeight.isFinite,
              outer + skipRoom,
              SizedBox(
                width: double.infinity,
                height: outer,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Semantics(
                        button: true,
                        label: label,
                        child: GestureDetector(
                          onTap: widget.measureAfter
                              ? widget.onMeasureAfter
                              : widget.done
                              ? widget.onUndo
                              : widget.measureFirst
                              ? widget.onMeasure
                              : widget.onTake,
                          child: ExcludeSemantics(
                            child: SizedBox(
                              width: outer,
                              height: outer,
                              child: Stack(
                                alignment: Alignment.center,
                                // 테가 받은 자리 밖으로 조금 나가도 자르지 않는다.
                                clipBehavior: Clip.none,
                                children: [
                                  OverflowBox(
                                    maxWidth: halo,
                                    maxHeight: halo,
                                    child: SizedBox(
                                      key: widget.focusKey,
                                      width: halo,
                                      height: halo,
                                      child: AnimatedBuilder(
                                        animation: _pulse,
                                        builder: (context, child) =>
                                            Transform.scale(
                                              scale: beating
                                                  ? _pulse.value
                                                  : 1.0,
                                              child: child,
                                            ),
                                        child: Container(
                                          width: halo,
                                          height: halo,
                                          decoration: const BoxDecoration(
                                            color: AppColors.pointHalo,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: size,
                                    height: size,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: fill,
                                      shape: BoxShape.circle,
                                    ),
                                    // 동그라미 안에 드는 네모는 지름의 0.7배다. 글씨를
                                    // 키운 기기에서도 그 안에서 줄여 담아 넘치지 않게 한다.
                                    child: SizedBox(
                                      width: size * 0.72,
                                      height: size * 0.72,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // 재기 때는 그림을 두지 않는다 — 글자 두 줄이
                                            // 이미 무엇을 하는지 말한다.
                                            if (!measuring) ...[
                                              Icon(
                                                widget.done
                                                    ? TablerIcons.arrow_back_up
                                                    : TablerIcons.check,
                                                size: iconSize,
                                                color: ink,
                                              ),
                                              const SizedBox(height: 2),
                                            ],
                                            for (final line in lines)
                                              Text(line, style: labelStyle),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.measureAfter && widget.onSkipMeasure != null)
                      Positioned(
                        // 테 바로 옆에 붙인다. 가운데 동그라미는 가운데 그대로
                        // 두고, 글자만 테 오른쪽 아래에 세운다.
                        left: skipLeft,
                        bottom: outer * 0.06,
                        child: SizedBox(
                          width: skipW,
                          child: _SkipMeasure(onTap: widget.onSkipMeasure!),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

const String _kSkipLabel = '측정 건너뛰기';

TextStyle _skipStyle() =>
    AppText.cardTitle(size: 17, color: AppColors.textSecondary);

/// 건너뛰는 글자 한 줄의 너비. 글자 배율도 따라 잰다.
double _skipWidth(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: _kSkipLabel, style: _skipStyle()),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width;
}

/// "측정 건너뛰기" — 원 오른쪽 아래 옆에 붙는 작은 글자.
///
/// 재는 일을 눈에 띄게 두되, 막지는 않는다. 센서를 지금 차고 있지
/// 않을 때 한 자리에 갇히면 오늘 홈은 쓸 수 없는 화면이 된다.
/// 원 밑에 두면 원이 그만큼 작아지므로 옆자리에 세운다.
class _SkipMeasure extends StatelessWidget {
  final VoidCallback onTap;

  const _SkipMeasure({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _kSkipLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.centerRight,
            child: Text(
              _kSkipLabel,
              // 한 줄로 둔다. 줄이 나뉘면 "건너뛰/기"처럼 끊겨 읽힌다.
              softWrap: false,
              overflow: TextOverflow.visible,
              style: _skipStyle(),
            ),
          ),
        ),
      ),
    );
  }
}

/// 동그라미 아래 두 칸 — "30분 뒤"와 "약 보기".
/// 다 드신 뒤에는 왼쪽이 드신 시각으로 바뀐다.
class _HomeTiles extends StatelessWidget {
  /// 알림 칸에 적을 말 — "다음 알람 18:00" 또는 "알림 꺼짐".
  final String alarmLabel;

  /// 복약 알림 설정으로. 소리로 울릴 시각을 거기서 고친다.
  final VoidCallback? onOpenAlarm;

  /// 센서 연결로. null이면 이미 쓰고 계신다.
  final VoidCallback? onConnectDevice;

  /// 센서 연결을 끊는다. 쓰고 계실 때만 둘다.
  final VoidCallback? onDisconnectDevice;
  final VoidCallback? onOpenMedicines;

  /// 도움말이 칸 하나하나를 따로 짚을 자리.
  final GlobalKey? alarmKey;
  final GlobalKey? sensorKey;

  const _HomeTiles({
    this.alarmKey,
    this.sensorKey,
    required this.alarmLabel,
    this.onOpenAlarm,
    this.onConnectDevice,
    this.onDisconnectDevice,
    this.onOpenMedicines,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          key: alarmKey,
          child: _tile(
            icon: TablerIcons.alarm,
            label: alarmLabel,
            onTap: onOpenAlarm,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          key: sensorKey,
          child: onConnectDevice != null
              ? _tile(
                  icon: TablerIcons.heart,
                  label: '센서 연결',
                  onTap: onConnectDevice,
                )
              : onDisconnectDevice != null
              ? _tile(
                  icon: TablerIcons.heart_off,
                  label: '기기 연결 해제',
                  onTap: onDisconnectDevice,
                  fontSize: 18,
                )
              : _tile(
                  icon: TablerIcons.pill,
                  label: '약 보기',
                  onTap: onOpenMedicines,
                ),
        ),
      ],
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color background = AppColors.surface,
    Color foreground = AppColors.textPrimary,
    double fontSize = 19,
  }) {
    return Semantics(
      button: onTap != null,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 100),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18),
              boxShadow: kCardShadow,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 34, color: foreground),
                const SizedBox(height: 6),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppText.cardTitle(size: fontSize, color: foreground),
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

/// "처방약이 3일분 남았어요" 한 줄.
class _RefillRow extends StatelessWidget {
  final int daysLeft;

  const _RefillRow({required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: kCardShadow,
      ),
      child: Row(
        children: [
          const Icon(
            TablerIcons.calendar_event,
            size: 24,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '처방약이 $daysLeft일분 남았어요',
              style: AppText.cardTitle(
                size: 17.5,
                color: AppColors.textBody,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeTopBar extends StatelessWidget {
  final String userName;

  /// 도움말 — 홈 화면을 짚어 가며 설명한다. 짚을 칸이 없는 화면에서는
  /// 비워 두고, 그때는 단추를 세우지 않는다.
  final VoidCallback? onHelp;
  final DateTime date;
  final bool easyMode;

  const HomeTopBar({
    super.key,
    required this.userName,
    this.onHelp,
    required this.date,
    this.easyMode = false,
  });

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    return SeniorHeader(
      background: AppColors.pageBg,
      // 바탕과 머리가 같은 흰색이라 선만 남는다. 카드 그림자가 이미
      // 본문을 가르므로 여기서 한 번 더 그을 이유가 없다.
      borderColor: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${date.month}월 ${date.day}일 ${_weekdays[date.weekday - 1]}요일',
                  style: AppText.body(size: 17, color: AppColors.textSecondary),
                ),
                Text(
                  userName.trim().isEmpty ? '오늘' : '$userName 님',
                  style: AppText.screenTitle(size: 21),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 쓰는 법이 궁금할 때 누르는 자리. 글자 단추를 두면 이름을
          // 밀어내므로 동그란 "i" 하나만 둔다.
          if (onHelp != null) HelpButton(onTap: onHelp!),
        ],
      ),
    );
  }
}

/// 지난 복약 행 — 이미 드신 시간대.
///

/// 접힌 복약 행을 펼쳤을 때 나오는 약 목록.
///

/// "약 드시는 시간" 창의 한 줄. 누르면 그 때의 시각을 바꾼다.
