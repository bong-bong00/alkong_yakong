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
import '../../../../core/widgets/senior_timeline.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medication/domain/medication_models.dart';
import '../../../medication/presentation/widgets/dose_flow_sheets.dart';
import '../../../easy_flow/domain/easy_flow.dart';
import '../../../easy_flow/presentation/easy_flow_shell.dart';
import '../../../medication/presentation/widgets/dose_guard_sheets.dart';
import '../../../profile/application/current_user_controller.dart';

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

  /// "먹었어요" 뒤 심박수를 재러 갈 때.
  final VoidCallback? onMeasure;

  /// 복약을 기록한 뒤 완료 화면으로.
  final VoidCallback? onDone;

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
    this.onDone,
    this.easyMode = false,
    this.onOpenMenu,
  });

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  /// 바로가기 접힘 상태. 기본은 접혀 있다 — 주 액션과 경쟁하지 않도록.
  bool _moreOpen = false;

  /// 재알림을 미뤘을 때 상단에 뜨는 안내.
  String? _snoozeNotice;

  @override
  void initState() {
    super.initState();
    // 잔여일이 0이면 홈에 들어오는 순간 리필 시트를 연다. 하루 한 번만.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskRefill());
  }

  Future<void> _maybeAskRefill() async {
    final controller = ref.read(medicationProvider.notifier);
    if (!mounted || !controller.shouldAskRefill) return;
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

  /// "먹었어요" — 바로 기록하지 않고 센서 착용부터 묻는다.
  Future<void> _take(DoseSlot slot) async {
    final controller = ref.read(medicationProvider.notifier);

    // 이미 기록된 시간대는 묻기 전에 막는다. 사후 안내가 아니라 사전 차단이다.
    if (ref.read(medicationProvider).doseOf(slot).taken) {
      await _showDuplicateGuard(slot);
      return;
    }

    final choice = await showWearSensorSheet(context);
    if (!mounted || choice == WearChoice.cancel) return;

    final outcome = controller.take(slot);
    if (!mounted) return;

    switch (outcome) {
      case DoseCheckOutcome.alreadyTaken:
        await _showDuplicateGuard(slot);
      case DoseCheckOutcome.tooLate:
        final proceed = await showLateDoseSheet(context: context, slot: slot);
        if (proceed && mounted) {
          controller.takeAnyway(slot);
          _afterRecord(choice);
        }
      case DoseCheckOutcome.recorded:
        _afterRecord(choice);
    }
  }

  void _afterRecord(WearChoice choice) {
    if (choice == WearChoice.wearingAndMeasure) {
      widget.onMeasure?.call();
    } else {
      widget.onDone?.call();
    }
  }

  Future<void> _showDuplicateGuard(DoseSlot slot) async {
    final dose = ref.read(medicationProvider).doseOf(slot);
    await showDuplicateDoseSheet(
      context: context,
      dose: dose,
      onUndo: () => ref.read(medicationProvider.notifier).undo(slot),
    );
  }

  void _snooze(DoseSlot slot) {
    final until = ref.read(medicationProvider.notifier).snooze(slot);
    setState(() => _snoozeNotice = '${DoseSlot.absoluteTime(until)}에 다시 알려드려요');
  }

  /// 하루를 시간 축으로 조립한다.
  ///
  /// 지난 복약 → (그 시간대에 잰 심박수) → 지금 → 앞으로 올 복약.
  /// **심박수를 안 잰 시간대에는 행을 만들지 않는다.** 빈 카드를 두면
  /// 재야 할 것을 안 잰 것처럼 보인다.
  List<Widget> _timeline(TodayMedication today, DoseEntry? next) {
    final rows = <Widget>[];

    void add(Widget child, {bool current = false, bool past = false}) {
      rows.add(TimelineRow(child: child, current: current, past: past));
      rows.add(kTimelineGap);
    }

    for (final dose in today.doses) {
      if (dose.taken) {
        add(_TakenRow(dose: dose), past: true);
        final check = dose.heartCheck;
        if (check != null) {
          add(
            _HeartRow(
              slotLabel: dose.slot.label,
              check: check,
              onTap: widget.onOpenHeartbeat,
            ),
            past: true,
          );
        }
        continue;
      }

      if (identical(dose, next)) {
        add(
          _NextDoseCard(
            today: today,
            dose: dose,
            onTake: () => _take(dose.slot),
            onSnooze: () => _snooze(dose.slot),
            onOpenDrug: widget.onOpenDrug,
          ),
          current: true,
        );
        continue;
      }

      add(_UpcomingRow(dose: dose));
    }

    // 다 드셨으면 축 끝에 완료 카드가 올라간다.
    if (next == null) {
      add(
        _AllDoneCard(
          today: today,
          onReTake: () => _take(today.doses.last.slot),
        ),
        current: true,
      );
    }

    // 마지막 행은 아래로 내려가는 선을 그리지 않는다.
    if (rows.isNotEmpty) {
      rows.removeLast();
      final last = rows.removeLast() as TimelineRow;
      rows.add(
        TimelineRow(
          current: last.current,
          past: last.past,
          last: true,
          child: last.child,
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(medicationProvider);
    final next = today.nextDose;
    final now = DateTime.now();

    return Column(
      children: [
        _Header(
          userName: ref.watch(currentUserNameProvider),
          date: now,
          easyMode: widget.easyMode,
          onOpenMenu: widget.onOpenMenu,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              // 쉬운 모드의 하단 바가 마지막 카드를 가리지 않게 한다.
              widget.easyMode ? kEasyBarScrollPadding : 28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_snoozeNotice != null) ...[
                  _SnoozeNotice(text: _snoozeNotice!),
                  const SizedBox(height: 12),
                ],
                if (today.interactionCards.isNotEmpty) ...[
                  for (final card in today.interactionCards) ...[
                    _InteractionPriorityCard(
                      card: card,
                      onOpenDrug: widget.onOpenDrug,
                      medicines: [
                        for (final dose in today.doses)
                          ...dose.medicines,
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ] else if ((today.interactionAlert ?? '').trim().isNotEmpty) ...[
                  SeniorCard(
                    padding: const EdgeInsets.all(18),
                    borderColor: AppColors.dangerBorder,
                    borderWidth: 2,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          TablerIcons.alert_triangle,
                          color: AppColors.danger,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '함께먹기 주의가 있어요',
                                style: AppText.cardTitle(
                                  size: 19,
                                  color: AppColors.danger,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                today.interactionAlert!,
                                style: AppText.body(size: 17),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (today.doses.isEmpty)
                  SeniorCard(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Text('등록된 약이 없어요', style: AppText.cardTitle(size: 22)),
                        const SizedBox(height: 8),
                        Text(
                          '처방전 사진을 찍으면 오늘 먹을 약을 알려드려요.',
                          textAlign: TextAlign.center,
                          style: AppText.body(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 14),
                        SeniorButton(
                          label: '처방전 사진 찍기',
                          onPressed: widget.onOpenPrescription,
                        ),
                      ],
                    ),
                  )
                else ...[
                  // 하루를 위에서 아래로 흐르는 시간 축으로 그린다.
                  // 지난 일 → 지금 → 앞으로 올 일 순서다.
                  SeniorButton(
                    label: '어제 · 지난주 보기',
                    icon: TablerIcons.chevron_up,
                    kind: SeniorButtonKind.secondary,
                    minHeight: 56,
                    fontSize: 20,
                    onPressed: widget.onOpenRecord,
                  ),
                  const SizedBox(height: 12),
                  ..._timeline(today, next),
                ],
                const SizedBox(height: 12),
                // 바로가기는 접어 둔다. 넷이 펼쳐져 있으면 주 액션과 경쟁한다.
                SeniorButton(
                  label: _moreOpen ? '다른 기능 접기  ⌃' : '다른 기능 보기  ⌄',
                  kind: SeniorButtonKind.secondary,
                  minHeight: 62,
                  fontSize: 21,
                  onPressed: () => setState(() => _moreOpen = !_moreOpen),
                ),
                if (_moreOpen) ...[
                  const SizedBox(height: 12),
                  _ShortcutGrid(
                    heartRate: today.heartRate,
                    onOpenMedicines: widget.onOpenMedicines,
                    onOpenHeartbeat: widget.onOpenHeartbeat,
                    onOpenChat: widget.onOpenChat,
                    onOpenPrescription: widget.onOpenPrescription,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 날짜 칩 + 모드 배지 + 아바타.
class _Header extends StatelessWidget {
  final String userName;
  final DateTime date;
  final bool easyMode;
  final VoidCallback? onOpenMenu;

  const _Header({
    required this.userName,
    required this.date,
    this.easyMode = false,
    this.onOpenMenu,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorHeader(
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${date.month}월 ${date.day}일',
                    style: AppText.cardTitle(
                      size: 21,
                      color: AppColors.point,
                      weight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '오늘',
                    style: AppText.cardTitle(size: 21, weight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          const ModeBadge(),
          const SizedBox(width: 10),
          if (easyMode && onOpenMenu != null)
            EasyMenuButton(onTap: onOpenMenu!)
          else
            InitialAvatar(name: userName, size: 52, background: AppColors.bg),
        ],
      ),
    );
  }
}

class _SnoozeNotice extends StatelessWidget {
  final String text;
  const _SnoozeNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.pointTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppText.label(size: 18.5, color: AppColors.pointInk),
      ),
    );
  }
}

class _InteractionPriorityCard extends StatelessWidget {
  final InteractionPriorityCard card;
  final void Function(Medicine)? onOpenDrug;
  final List<Medicine> medicines;

  const _InteractionPriorityCard({
    required this.card,
    required this.onOpenDrug,
    required this.medicines,
  });

  Medicine? _byCode(String? code) {
    final needle = (code ?? '').trim();
    if (needle.isEmpty) return null;
    for (final medicine in medicines) {
      if ((medicine.medicineCode ?? '').trim() == needle) return medicine;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.all(18),
      borderColor: AppColors.dangerBorder,
      borderWidth: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '함께먹기 주의가 있어요',
            style: AppText.cardTitle(size: 19, color: AppColors.danger),
          ),
          const SizedBox(height: 6),
          Text(
            '${card.nameA} ↔ ${card.nameB}',
            style: AppText.body(size: 18),
          ),
          const SizedBox(height: 8),
          Text(card.reason, style: AppText.body(size: 17)),
          if (card.riskFactor.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '성분 위험요소: ${card.riskFactor}',
              style: AppText.label(size: 17),
            ),
          ],
          if (!card.reason.contains('확인해')) ...[
            const SizedBox(height: 8),
            Text(
              '약국이나 병원에 한 번 확인해 주세요.',
              style: AppText.label(size: 17, color: AppColors.danger),
            ),
          ],
          if (onOpenDrug != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final medicine in [_byCode(card.codeA), _byCode(card.codeB)])
                  if (medicine != null)
                    OutlinedButton(
                      onPressed: () => onOpenDrug!(medicine),
                      child: Text(_shortName(medicine.ingredient)),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _shortName(String name) {
    final trimmed = name.trim();
    final index = trimmed.indexOf('(');
    if (index > 0) return trimmed.substring(0, index).trim();
    return trimmed;
  }
}

/// 지금 드실 약 — 이 화면의 주인공.
class _NextDoseCard extends StatelessWidget {
  final TodayMedication today;
  final DoseEntry dose;
  final VoidCallback onTake;
  final VoidCallback onSnooze;
  final void Function(Medicine)? onOpenDrug;

  const _NextDoseCard({
    required this.today,
    required this.dose,
    required this.onTake,
    required this.onSnooze,
    required this.onOpenDrug,
  });

  @override
  Widget build(BuildContext context) {
    final others = today.doses.where((d) => d.slot != dose.slot).toList();
    final daysLeft = today.daysLeft;
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (daysLeft != null) ...[
            DaysLeftRow(daysLeft: daysLeft, phrase: today.daysLeftPhrase),
            const SizedBox(height: 12),
          ],
          LabelValueRow(
            label: Text(dose.slot.spokenTime, style: AppText.bigTime(size: 36)),
            value: Text(
              '눌러서 설명 보기',
              textAlign: TextAlign.right,
              style: AppText.label(size: 16.5, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < dose.medicines.length; i++) ...[
            if (i > 0) const SeniorDivider(),
            _MedicineRow(
              medicine: dose.medicines[i],
              onTap: onOpenDrug == null
                  ? null
                  : () => onOpenDrug!(dose.medicines[i]),
            ),
          ],
          const SizedBox(height: 12),
          SeniorButton(label: '먹었어요', onPressed: onTake),
          const SizedBox(height: 10),
          SeniorButton(
            label: '30분 뒤에 다시 알려주기',
            kind: SeniorButtonKind.secondary,
            minHeight: 62,
            fontSize: 20,
            onPressed: onSnooze,
          ),
          if (others.any((d) => d.taken)) ...[
            const SizedBox(height: 12),
            _OtherDosesBlock(doses: others.where((d) => d.taken).toList()),
          ],
        ],
      ),
    );
  }
}

/// 약 한 줄 — 사진, 이름, 효능, 생김새, 개수.
class _MedicineRow extends StatelessWidget {
  final Medicine medicine;
  final VoidCallback? onTap;

  const _MedicineRow({required this.medicine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            PillPhoto(size: 60),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicine.displayName,
                    style: AppText.cardTitle(size: 21),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((medicine.ingredientLabel ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '주성분: ${medicine.ingredientLabel!}',
                      style: AppText.caption(
                        size: 16.5,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (medicine.cardSpoken != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      medicine.cardSpoken!,
                      style: AppText.caption(size: 17),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              medicine.amount,
              style: AppText.cardTitle(size: 20, color: AppColors.point),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const SeniorChevron(),
            ],
          ],
        ),
      ),
    );
  }
}

/// 오늘 이미 드신 다른 약.
class _OtherDosesBlock extends StatelessWidget {
  final List<DoseEntry> doses;
  const _OtherDosesBlock({required this.doses});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('오늘 다른 약', style: AppText.label(size: 17.5)),
          const SizedBox(height: 10),
          for (final dose in doses)
            for (final medicine in dose.medicines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const PillPhoto(size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medicine.displayName,
                            style: AppText.label(
                              size: 18,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (medicine.effect != null)
                            Text(
                              medicine.effect!,
                              style: AppText.caption(size: 16.5),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${dose.slot.label} ✓',
                      style: AppText.cardTitle(
                        size: 16.5,
                        color: AppColors.point,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// 오늘 약을 다 드신 뒤의 카드.
class _AllDoneCard extends StatelessWidget {
  final TodayMedication today;
  final VoidCallback onReTake;

  const _AllDoneCard({required this.today, required this.onReTake});

  @override
  Widget build(BuildContext context) {
    final daysLeft = today.daysLeft;
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.pointTint,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  '✓',
                  style: AppText.cardTitle(size: 20, color: AppColors.point),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('오늘 약 다 드셨어요', style: AppText.cardTitle(size: 22)),
                    Text(
                      '다음 약은 내일 ${today.doses.first.slot.spokenTime}',
                      style: AppText.caption(size: 17.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (daysLeft != null) ...[
            DaysLeftRow(daysLeft: daysLeft, phrase: today.daysLeftPhrase),
            const SizedBox(height: 12),
          ],
          SeniorButton(
            label: '${today.doses.last.slot.label} 약 다시 누르기',
            kind: SeniorButtonKind.neutral,
            minHeight: 60,
            fontSize: 19,
            onPressed: onReTake,
          ),
        ],
      ),
    );
  }
}


/// 2×2 바로가기.
class _ShortcutGrid extends StatelessWidget {
  /// 잰 적이 없으면 null. 숫자 자리를 비워 둔다.
  final int? heartRate;
  final VoidCallback? onOpenMedicines;
  final VoidCallback? onOpenHeartbeat;
  final VoidCallback? onOpenChat;
  final VoidCallback? onOpenPrescription;

  const _ShortcutGrid({
    required this.heartRate,
    required this.onOpenMedicines,
    required this.onOpenHeartbeat,
    required this.onOpenChat,
    required this.onOpenPrescription,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Shortcut(
                  icon: TablerIcons.pill,
                  label: '내 약 목록',
                  onTap: onOpenMedicines,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Shortcut(
                  icon: TablerIcons.activity_heartbeat,
                  label: '심박수',
                  trailing: heartRate == null ? null : '$heartRate',
                  onTap: onOpenHeartbeat,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Shortcut(
                  icon: TablerIcons.message_circle_question,
                  label: 'AI 약사 상담',
                  onTap: onOpenChat,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Shortcut(
                  icon: TablerIcons.prescription,
                  label: '처방전 넣기',
                  onTap: onOpenPrescription,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;

  const _Shortcut({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.pointTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: ExcludeSemantics(
              child: Icon(icon, size: 26, color: AppColors.point),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text(label, style: AppText.cardTitle(size: 19))),
              if (trailing != null)
                Text(
                  trailing!,
                  style: AppText.cardTitle(size: 23, color: AppColors.point),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 지난 복약 행 — 이미 드신 시간대.
///
/// 제목은 19/900. "지금" 행의 30/900과 크기가 달라야 무엇이 지금 할 일인지
/// 한눈에 잡힌다. 모두 같은 크기로 만들면 타임라인의 효과가 사라진다.
class _TakenRow extends StatelessWidget {
  final DoseEntry dose;

  const _TakenRow({required this.dose});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${dose.slot.spokenTime} · ${dose.medicines.length}알',
                  style: AppText.cardTitle(size: 19),
                ),
                Text('드셨어요', style: AppText.caption(size: 17)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ExcludeSemantics(
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.pointTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                TablerIcons.check,
                size: 22,
                color: AppColors.point,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 심박수 측정 행 — 그 시간대에 실제로 잰 것이 있을 때만 붙는다.
class _HeartRow extends StatelessWidget {
  final String slotLabel;
  final DoseHeartCheck check;
  final VoidCallback? onTap;

  const _HeartRow({
    required this.slotLabel,
    required this.check,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$slotLabel 심박수', style: AppText.cardTitle(size: 19)),
                Text(
                  '${check.before} → ${check.after} · ${check.phrase}',
                  style: AppText.caption(
                    size: 17,
                    color: check.isFast
                        ? AppColors.danger
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const ExcludeSemantics(
            child: Icon(
              TablerIcons.chevron_right,
              size: 24,
              color: AppColors.inactive,
            ),
          ),
        ],
      ),
    );
  }
}

/// 앞으로 올 복약 행 — 회색으로 물려 둔다. 지금 할 일이 아니다.
class _UpcomingRow extends StatelessWidget {
  final DoseEntry dose;

  const _UpcomingRow({required this.dose});

  /// "2시간 뒤". 이미 지난 시각이면 비운다.
  String get _inPhrase {
    final now = DateTime.now();
    final at = dose.slot.todayAt(now);
    final minutes = at.difference(now).inMinutes;
    if (minutes <= 0) return '';
    if (minutes < 60) return '$minutes분 뒤';
    return '${(minutes / 60).round()}시간 뒤';
  }

  @override
  Widget build(BuildContext context) {
    final inPhrase = _inPhrase;
    return SeniorCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${dose.slot.spokenTime} · ${dose.medicines.length}알',
              style: AppText.cardTitle(
                size: 19,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          if (inPhrase.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              inPhrase,
              style: AppText.label(size: 17, color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
