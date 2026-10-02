import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/mode_badge.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../../core/widgets/senior_sheet.dart';
import '../../../../core/widgets/senior_wheel.dart';
import '../../../../core/network/api_client.dart';
import '../../../guardian/application/guardians_provider.dart';
import '../../../guardian/data/guardian_repository.dart';
import '../../../medication/application/dose_times.dart';
import '../../../biosignal/application/heart_device.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../reminder/application/alarm_preferences.dart';
import '../../../reminder/application/reminder_notifications.dart';
import '../../../reminder/presentation/screens/alarm_settings_screen.dart';
import '../../../medication/domain/medication_models.dart';
import '../../../medication/presentation/widgets/dose_flow_sheets.dart';
import '../../../easy_flow/domain/easy_flow.dart';
import '../../../easy_flow/presentation/easy_flow_shell.dart';
import '../../../medication/presentation/widgets/dose_guard_sheets.dart';
import '../../../profile/application/current_user_controller.dart';
import 'package:go_router/go_router.dart';
import '../../../medicines/application/family_medicine_inbox.dart';
import '../../../medicines/application/user_medicines_controller.dart';

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
  final void Function(DoseSlot slot)? onMeasure;

  /// 약을 들기 **전에** 재러 갈 때. 다 재면 잰 값을 돌려준다.
  /// 기기를 쓰는 분에게만 쓰인다.
  final Future<int?> Function(DoseSlot slot)? onMeasureBefore;

  /// 복약을 기록한 뒤 완료 화면으로. 방금 기록한 시간대를 함께 넘긴다.
  final void Function(DoseSlot slot)? onDone;

  /// 쉬운 모드인지. 헤더의 아바타가 "메뉴" 버튼으로 바뀌고
  /// 스크롤 아래 여백이 하단 바만큼 늘어난다.
  final bool easyMode;

  /// 쉬운 모드에서 메뉴를 열 때.
  final VoidCallback? onOpenMenu;

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
    this.onOpenMenu,
  });

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  /// 방금 기록한 시간대. 파란 띠로 알리고, X를 누르면 사라진다.
  DoseSlot? _recordedSlot;

  /// 때마다 먹기 전에 잰 심박수. 다음 때로 넘어가면 그 때에는 값이 없어
  /// 다시 1단계부터 시작한다.
  final Map<DoseSlot, int> _beforeBpm = {};

  @override
  void initState() {
    super.initState();
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

  /// 때 칸을 눌렀을 때 — 아침·점심·저녁이 몇 시인지 보여 주고 그 자리에서
  /// 고친다.
  ///
  /// 여기서 고치는 것은 **화면에 적는 시각**이다. 소리로 울리는 시각은
  /// "알림 시간"에서 따로 고른다.
  Future<void> _showDoseTimes() async {
    await SeniorSheet.show<void>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (consumerContext, sheetRef, _) {
          final times = sheetRef.watch(doseTimesProvider);
          return SeniorSheet(
            title: '약 드시는 시간',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final slot in DoseSlot.values) ...[
                  if (slot != DoseSlot.values.first) const SeniorDivider(),
                  _SlotTimeRow(
                    label: slot.label,
                    clock: times.clock(slot),
                    onTap: () => _changeDoseTime(sheetContext, slot),
                  ),
                ],
              ],
            ),
            actions: [
              SeniorButton(
                label: '닫기',
                kind: SeniorButtonKind.secondary,
                minHeight: 66,
                fontSize: 21,
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 한 때의 시각을 바꾼다.
  ///
  /// **소리로 울리는 시각은 건드리지 않는다.** 여기서 고치는 것은 화면에
  /// 적는 시각뿐이고, 알림은 "알림 시간"에서 따로 고른다.
  Future<void> _changeDoseTime(BuildContext sheetContext, DoseSlot slot) async {
    final times = ref.read(doseTimesProvider);
    final current = times.of(slot);
    final time = await showSeniorClockWheel(
      context: sheetContext,
      title: '${slot.label}, 몇 시에 드세요?',
      initialMinutes: current,
    );
    if (time == null || time == current) return;
    await ref
        .read(doseTimesProvider.notifier)
        .update(times.withTime(slot, time));

    if (!mounted) return;
    showSeniorSnackbar(
      context,
      '${slot.label}을 ${DoseTimes.clockOf(time)}로 바꿨어요',
    );
  }

  /// 홈 알림 칸에 적을 말. 다음에 울릴 시각만 적는다 — 자명종 그림이
  /// 이미 알림이라고 말하고 있다.
  static String _nextAlarmLabel(AlarmPreferences alarm) {
    final times = alarm.ringingTimes;
    if (!alarm.autoAlarm || times.isEmpty) return '알림 꺼짐';
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    // 오늘 남은 것 중 첫 번째, 없으면 내일 첫 번째.
    final next = times.firstWhere(
      (t) => t > minutes,
      orElse: () => times.first,
    );
    return AlarmPreferences.clock(next);
  }

  /// "알림 시간" 칸 — 소리로 울릴 시각을 고치러 간다.
  Future<void> _openAlarmSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AlarmSettingsScreen()),
    );
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
          {'name': medicine.displayName, 'dose': medicine.amount},
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
    });
    // 기기를 쓰는 분은 드신 뒤에 한 번 더 잰다.
    if (ref.read(heartDevicePairedProvider)) {
      widget.onMeasure?.call(slot);
    } else {
      widget.onDone?.call(slot);
    }
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

    return Container(
      color: AppColors.pageBg,
      child: Column(
        children: [
          // 간편 화면에서는 쉘이 위에 걸음 표시와 "일반 화면으로"를 둔다.
          // 여기서 또 머리를 그리면 두 줄이 겹친다.
          if (!widget.easyMode)
            HomeTopBar(
              userName: ref.watch(currentUserNameProvider),
              date: now,
              easyMode: widget.easyMode,
              onOpenMenu: widget.onOpenMenu,
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
                        today: today,
                        next: next,
                        times: ref.watch(doseTimesProvider),
                        onSetTimes: _showDoseTimes,
                      ),
                      const SizedBox(height: 8),
                      // 누를 수 있다는 것을 모르면 평생 못 누른다. 한 줄만 적는다.
                      Text(
                        '아침/점심/저녁을 누르면 복약 시간을 바꿔요',
                        textAlign: TextAlign.left,
                        style: AppText.caption(size: 16),
                      ),
                      if (usesDevice && next != null) ...[
                        const SizedBox(height: 14),
                        _HeartSteps(beforeBpm: _beforeBpm[next.slot]),
                      ],
                      const SizedBox(height: 18),
                      // 남는 세로 자리를 그대로 받아 그 안에 맞춘다.
                      _Fill(
                        scrolls: scrolls,
                        child: _BigDoseButton(
                          done: next == null,
                          // 기기를 쓰는 분은 먹기 전에 먼저 잰다.
                          measureFirst:
                              next != null &&
                              usesDevice &&
                              _beforeBpm[next.slot] == null,
                          compact: usesDevice && next != null,
                          onMeasure: next == null
                              ? null
                              : () => _measureBefore(next.slot),
                          onTake: next == null ? null : () => _take(next.slot),
                          onUndo: next != null
                              ? null
                              : () => _undo(
                                  _recordedSlot ?? today.doses.last.slot,
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _HomeTiles(
                        alarmLabel: _nextAlarmLabel(
                          ref.watch(alarmPreferencesProvider),
                        ),
                        onOpenAlarm: _openAlarmSettings,
                        onOpenMedicines: widget.onOpenMedicines,
                      ),
                      if (today.daysLeft != null) ...[
                        const SizedBox(height: 16),
                        _RefillRow(daysLeft: today.daysLeft!),
                      ],
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

/// 아침·점심·저녁 세 칸. 드신 때는 흰 칩에 체크, 다음 때는 파란 칩,
/// 약이 없는 때는 회색 칩에 "없음".
///
/// 칸 아래에 그 때가 몇 시인지 적는다. 셋 다 적는다 — 한 칸에만 적혀
/// 있으면 왜 거기만 적혔는지 알 수 없다. 아직 시간을 맞춘 적이 없어도
/// 기본 시각(아침 8시·점심 12시·저녁 6시)이 적힌다.
class _SlotChips extends StatelessWidget {
  final TodayMedication today;
  final DoseEntry? next;

  /// 약 드시는 시각 — 소리로 울리는 시각과는 따로 간다.
  final DoseTimes times;

  /// 칸을 눌렀을 때 — "약 드시는 시간" 창을 연다.
  final VoidCallback onSetTimes;

  const _SlotChips({
    required this.today,
    required this.next,
    required this.times,
    required this.onSetTimes,
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

  Widget _chip(DoseSlot slot) {
    final dose = today.doses.where((d) => d.slot == slot).firstOrNull;
    final isNext = next?.slot == slot;
    final taken = dose?.taken ?? false;

    final under = dose == null ? '없음' : times.clock(slot);
    final background = dose == null
        ? AppColors.neutralFill
        : isNext
        ? AppColors.pointFill
        : AppColors.surface;
    final foreground = dose == null
        ? AppColors.textSecondary
        : isNext
        ? Colors.white
        : AppColors.point;

    return Semantics(
      button: true,
      label: dose == null
          ? '${slot.label} 약 없음, 눌러서 시간 설정하기'
          : taken
          ? '${slot.label} ${times.clock(slot)}, 드셨어요, 눌러서 시간 설정하기'
          : '${slot.label} ${times.clock(slot)}, 눌러서 시간 설정하기',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onSetTimes,
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
                      style: AppText.cardTitle(size: 16, color: foreground),
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

  const _HeartSteps({required this.beforeBpm});

  @override
  Widget build(BuildContext context) {
    final done = beforeBpm != null;
    final current = done ? 1 : 0;
    final labels = [done ? '먹기 전 $beforeBpm회' : '먹기 전 재기', '먹었어요', '먹은 뒤 재기'];

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
                weight: now ? FontWeight.w900 : FontWeight.w600,
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
  final VoidCallback? onMeasure;
  final VoidCallback? onTake;
  final VoidCallback? onUndo;

  const _BigDoseButton({
    required this.done,
    this.measureFirst = false,
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

  @override
  Widget build(BuildContext context) {
    final label = widget.done
        ? '취소하기'
        : widget.measureFirst
        ? '심박수 재기'
        : '먹었어요';
    // 먹기 전 재기는 왜 지금 재는지 한 줄 더 말한다. "심박수 재기"만 있으면
    // 약을 안 누르고 왜 이걸 누르는지 모른다.
    final sub = widget.measureFirst && !widget.done ? '약 먹기 전에' : null;
    final fill = widget.done ? AppColors.surface : AppColors.pointFill;
    final ink = widget.done ? AppColors.textPrimary : Colors.white;
    // 움직임을 꺼 둔 기기에서는 뛰지 않는다. 다 드신 뒤에도 멈춘다 —
    // 누를 것이 없는데 눈을 끌 이유가 없다.
    final beating = !widget.done && !MediaQuery.disableAnimationsOf(context);
    if (beating) {
      if (!_beat.isAnimating) _beat.repeat();
    } else if (_beat.isAnimating) {
      _beat.stop();
      _beat.value = 0;
    }

    return LayoutBuilder(
      builder: (context, box) {
        // 받은 자리 안에 테까지 들어가야 한다. 가로·세로 중 좁은 쪽에
        // 맞추되, 글자를 읽을 수 있는 크기 아래로는 줄이지 않는다.
        // 가로는 양옆을 한 뼘씩 비워 둔다. 화면 폭을 꽉 채우면
        // 동그라미가 벽에 낀 것처럼 답답해 보인다.
        final room = math.min(
          (box.maxWidth.isFinite ? box.maxWidth : 320) - 56,
          box.maxHeight.isFinite ? box.maxHeight : 320,
        );
        // 걸음 표시가 위에 붙으면 자리가 좁다. 그때는 한 치수 줄인다.
        final outer = room
            .clamp(180.0, widget.compact ? 230.0 : 300.0)
            .toDouble();
        final ring = outer * 0.11;
        final size = outer - ring * 2;
        // 글자와 아이콘은 지름을 따라간다. 동그라미만 커지고 글자가
        // 그대로면 가운데가 비어 보인다.
        final labelSize = (size * 0.135).clamp(24.0, 34.0).toDouble();
        final iconSize = (size * 0.24).clamp(44.0, 66.0).toDouble();
        final labelStyle = AppText.cardTitle(size: labelSize, color: ink);

        return Center(
          child: Semantics(
            button: true,
            label: label,
            child: GestureDetector(
              onTap: widget.done
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
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) => Transform.scale(
                          scale: beating ? _pulse.value : 1.0,
                          child: child,
                        ),
                        child: Container(
                          width: outer,
                          height: outer,
                          decoration: const BoxDecoration(
                            color: AppColors.pointRing,
                            shape: BoxShape.circle,
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
                                Icon(
                                  widget.done
                                      ? TablerIcons.arrow_back_up
                                      : widget.measureFirst
                                      ? TablerIcons.heart_filled
                                      : TablerIcons.check,
                                  size: iconSize,
                                  color: ink,
                                ),
                                const SizedBox(height: 2),
                                Text(label, style: labelStyle),
                                if (sub != null)
                                  Text(
                                    sub,
                                    style: AppText.cardTitle(
                                      size: labelSize * 0.62,
                                      color: AppColors.onPointMuted,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
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
        );
      },
    );
  }
}

/// 동그라미 아래 두 칸 — "30분 뒤"와 "약 보기".
/// 다 드신 뒤에는 왼쪽이 드신 시각으로 바뀐다.
class _HomeTiles extends StatelessWidget {
  /// 알림 칸에 적을 말 — "18:00" 또는 "알림 꺼짐".
  final String alarmLabel;

  /// 복약 알림 설정으로. 소리로 울릴 시각을 거기서 고친다.
  final VoidCallback? onOpenAlarm;
  final VoidCallback? onOpenMedicines;

  const _HomeTiles({
    required this.alarmLabel,
    this.onOpenAlarm,
    this.onOpenMedicines,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _tile(
            icon: TablerIcons.alarm,
            label: alarmLabel,
            onTap: onOpenAlarm,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _tile(
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
                weight: FontWeight.w700,
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
  final DateTime date;
  final bool easyMode;
  final VoidCallback? onOpenMenu;

  const HomeTopBar({
    super.key,
    required this.userName,
    required this.date,
    this.easyMode = false,
    this.onOpenMenu,
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
          // 지금 어느 화면인지는 두 모드 모두에서 보여야 한다.
          // 간편 화면에서는 그 옆에 메뉴 단추가 하나 더 붙는다.
          const Flexible(child: ModeBadge()),
          if (easyMode && onOpenMenu != null) ...[
            const SizedBox(width: 10),
            EasyMenuButton(onTap: onOpenMenu!),
          ],
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
class _SlotTimeRow extends StatelessWidget {
  final String label;
  final String clock;
  final VoidCallback onTap;

  const _SlotTimeRow({
    required this.label,
    required this.clock,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label $clock, 누르면 바꿔요',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            color: Colors.transparent,
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              children: [
                Expanded(child: Text(label, style: AppText.label(size: 20))),
                Text(clock, style: AppText.cardTitle(size: 21)),
                const SizedBox(width: 8),
                const Icon(
                  Icons.expand_more_rounded,
                  size: 24,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
