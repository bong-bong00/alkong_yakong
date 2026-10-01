import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/senior_button.dart';
import '../../../core/widgets/senior_card.dart';
import '../../biosignal/application/heart_sensor.dart';
import '../../biosignal/domain/heart_data.dart';
import '../../medication/application/medication_controller.dart';
import '../../medication/domain/medication_models.dart';
import '../../medication/presentation/widgets/dose_guard_sheets.dart';
import '../../reminder/application/alarm_preferences.dart';

/// 쉬운 화면의 복약 한 바퀴 (명세서 76~85).
///
/// 여덟 걸음을 한 걸음에 하나씩만 보여 준다.
/// 1 약 드실 시간 · 2 가슴 띠 차기 · 3 먹기 전 재는 중 · 4 잘 쟀어요
/// 5 약 드세요 · 6 한 번 더 재요 · 7 먹은 후 재는 중 · 8 결과
/// 그리고 다 끝나면 "오늘 다 했어요" 한 장 (85).
///
/// 심박수를 건너뛰어도 복약 기록은 그대로 남는다 — 재는 일은 곁가지다.
enum EasyDoseStep {
  /// 76 · 약 드실 시간이에요.
  time,

  /// 77 · 심박 센서를 차 주세요.
  wear,

  /// 78 · 먹기 전 재는 중.
  measureBefore,

  /// 79 · 먹기 전 잘 쟀어요.
  beforeDone,

  /// 80 · 이 약을 드세요.
  take,

  /// 81 · 한 번 더 재요.
  afterAsk,

  /// 82 · 먹은 후 재는 중.
  measureAfter,

  /// 83·84 · 결과.
  result,

  /// 85 · 오늘 다 했어요.
  allDone,
}

/// 걸음 표시에 쓰는 번호. [EasyDoseStep.allDone]은 세지 않는다.
int? easyStepNumber(EasyDoseStep step) =>
    step == EasyDoseStep.allDone ? null : EasyDoseStep.values.indexOf(step) + 1;

/// 걸음 표시의 칸 수.
const int kEasyDoseSteps = 8;

class EasyDoseFlow extends ConsumerStatefulWidget {
  /// 85의 "더 보기"에서 가는 곳.
  final VoidCallback? onOpenMedicines;
  final VoidCallback? onOpenRecord;
  final VoidCallback? onOpenHeart;
  final VoidCallback? onOpenMyInfo;
  final VoidCallback? onOpenChat;

  /// 밖에서 넣어 주는 센서. 없으면 잴 때 하나 만들어 쓴다.
  final HeartSensor? sensor;

  const EasyDoseFlow({
    super.key,
    this.onOpenMedicines,
    this.onOpenRecord,
    this.onOpenHeart,
    this.onOpenMyInfo,
    this.onOpenChat,
    this.sensor,
  });

  @override
  ConsumerState<EasyDoseFlow> createState() => _EasyDoseFlowState();
}

class _EasyDoseFlowState extends ConsumerState<EasyDoseFlow> {
  /// 재는 시간. 측정 화면과 같은 값을 쓴다.
  static const int _measureSeconds = 45;

  EasyDoseStep _step = EasyDoseStep.time;
  final List<EasyDoseStep> _history = <EasyDoseStep>[];

  /// 이 바퀴에서 잰 값. 재지 않았으면 null — 숫자를 지어내지 않는다.
  int? _before;
  int? _after;

  /// 이 바퀴에서 기록한 시간대. 되돌릴 때 쓴다.
  DoseSlot? _recordedSlot;

  HeartSensor? _sensor;
  bool _ownsSensor = false;

  /// 센서가 값을 알려 줬을 때 setState를 빌드 중에 부르지 않으려는 자리.
  bool _sensorUpdatePending = false;

  @override
  void dispose() {
    _sensor?.removeListener(_onSensor);
    if (_ownsSensor) _sensor?.dispose();
    super.dispose();
  }

  // ── 걸음 옮기기 ────────────────────────────────────────

  void _goTo(EasyDoseStep step) {
    if (step == _step) return;
    setState(() {
      _history.add(_step);
      if (_history.length > 20) _history.removeAt(0);
      _step = step;
    });
  }

  void _back() {
    if (_history.isEmpty) return;
    final previous = _history.removeLast();
    // 재던 중으로 되돌아가면 처음부터 다시 잰다.
    setState(() => _step = previous);
    if (previous == EasyDoseStep.measureBefore ||
        previous == EasyDoseStep.measureAfter) {
      _startMeasuring(
        previous == EasyDoseStep.measureBefore
            ? HeartMeasurementContext.beforeMedication
            : HeartMeasurementContext.afterMedication,
      );
    }
  }

  // ── 심박수 재기 ────────────────────────────────────────

  void _startMeasuring(HeartMeasurementContext context) {
    final existing = _sensor ?? widget.sensor;
    if (existing == null) {
      final sensor = HeartSensor();
      _sensor = sensor;
      _ownsSensor = true;
      sensor.addListener(_onSensor);
      unawaited(sensor.start(measurementContext: context));
      return;
    }
    if (_sensor == null) {
      _sensor = existing;
      existing.addListener(_onSensor);
    }
    if (existing.status == HeartSensorStatus.streaming) {
      existing.beginMeasurement(measurementContext: context);
    } else {
      unawaited(existing.start(measurementContext: context));
    }
  }

  void _onSensor() {
    if (!mounted || _sensorUpdatePending) return;
    _sensorUpdatePending = true;
    // 센서는 빌드 중에도 값을 던진다. 한 틱 미뤄서 받는다.
    scheduleMicrotask(() {
      _sensorUpdatePending = false;
      if (!mounted) return;
      setState(() {});
      _afterSensorUpdate();
    });
  }

  /// 저장까지 끝났으면 다음 걸음으로 넘어간다.
  void _afterSensorUpdate() {
    final sensor = _sensor;
    if (sensor == null) return;
    if (sensor.saveStatus != HeartSaveStatus.saved) return;
    final bpm = sensor.savedBpm;
    if (bpm == null) return;

    if (_step == EasyDoseStep.measureBefore) {
      setState(() => _before = bpm);
      _goTo(EasyDoseStep.beforeDone);
    } else if (_step == EasyDoseStep.measureAfter) {
      setState(() => _after = bpm);
      _goTo(EasyDoseStep.result);
    }
  }

  /// 재는 것을 그만둔다. 복약은 그대로 이어 간다.
  void _stopMeasuring(EasyDoseStep next) {
    _sensor?.stop();
    _goTo(next);
  }

  // ── 복약 기록 ──────────────────────────────────────────

  Future<void> _record(DoseSlot slot) async {
    final controller = ref.read(medicationProvider.notifier);
    final outcome = await controller.take(slot);
    if (!mounted) return;

    switch (outcome) {
      case DoseCheckOutcome.alreadyTaken:
        await showDuplicateDoseSheet(
          context: context,
          dose: ref.read(medicationProvider).doseOf(slot),
          onUndo: () => controller.undo(slot),
        );
        return;
      case DoseCheckOutcome.tooLate:
        final proceed = await showLateDoseSheet(context: context, slot: slot);
        if (!proceed || !mounted) return;
        await controller.takeAnyway(slot);
        if (!mounted) return;
      case DoseCheckOutcome.recorded:
        break;
    }

    setState(() => _recordedSlot = slot);
    // 센서를 차고 재 뒀으면 먹은 뒤에도 한 번 잰다. 안 쟀으면 묻지 않는다.
    _goTo(_before == null ? EasyDoseStep.allDone : EasyDoseStep.afterAsk);
  }

  void _undoRecord() {
    final slot = _recordedSlot;
    if (slot == null) return;
    ref.read(medicationProvider.notifier).undo(slot);
    setState(() {
      _recordedSlot = null;
      _after = null;
      _history.clear();
      _step = EasyDoseStep.take;
    });
  }

  // ── 그리기 ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(medicationProvider);
    final dose = today.doseOf(_recordedSlot ?? DoseSlot.morning);
    final next = today.nextDose;

    // 못 불러온 것을 "다 드셨어요"로 말하지 않는다.
    if (_step == EasyDoseStep.time &&
        next == null &&
        today.fetchStatus != MedicationFetchStatus.ready) {
      return _waiting(today.fetchStatus);
    }

    // 드실 약이 없으면 첫 걸음을 보여 줄 이유가 없다.
    if (_step == EasyDoseStep.time && next == null) {
      return _allDone(today);
    }

    switch (_step) {
      case EasyDoseStep.time:
        return _time(next!);
      case EasyDoseStep.wear:
        return _wear();
      case EasyDoseStep.measureBefore:
        return _measuring(
          step: EasyDoseStep.measureBefore,
          lead: '먹기 전 심박을',
          next: EasyDoseStep.take,
        );
      case EasyDoseStep.beforeDone:
        return _beforeDone();
      case EasyDoseStep.take:
        return _take(next ?? dose);
      case EasyDoseStep.afterAsk:
        return _afterAsk();
      case EasyDoseStep.measureAfter:
        return _measuring(
          step: EasyDoseStep.measureAfter,
          lead: '먹은 후 심박을',
          next: EasyDoseStep.allDone,
        );
      case EasyDoseStep.result:
        return _result(today);
      case EasyDoseStep.allDone:
        return _allDone(today);
    }
  }

  /// 76 · 약 드실 시간이에요.
  Widget _time(DoseEntry dose) {
    return _EasyStepPage(
      step: EasyDoseStep.time,
      lead: '${dose.slot.label} 약',
      title: '드실 시간이에요',
      subtitle: '약 드시기 전에 심박부터 재요',
      body: [_MedicineCard(medicines: dose.medicines)],
      primary: _EasyAction(
        label: '복약 전 심박 측정',
        icon: Icons.favorite_rounded,
        onPressed: () => _goTo(EasyDoseStep.wear),
      ),
      secondaries: [
        _EasyAction(
          label: '안 잴래요',
          icon: Icons.skip_next_rounded,
          onPressed: () => _goTo(EasyDoseStep.take),
        ),
      ],
    );
  }

  /// 77 · 심박 센서를 차 주세요.
  Widget _wear() {
    return _EasyStepPage(
      step: EasyDoseStep.wear,
      lead: '심박 센서를',
      title: '차 주세요',
      body: [
        SeniorCard(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: SizedBox(
            height: 120,
            child: Center(
              child: Text(
                '차는 모습 그림 자리',
                style: AppText.label(size: 17, color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _NumberedCard(lines: ['팔꿈치 위에 차요', '동그란 면이 살에 닿게', '밴드를 조금 조여요']),
      ],
      primary: _EasyAction(
        label: '다 찼어요',
        icon: Icons.check_rounded,
        onPressed: () {
          _goTo(EasyDoseStep.measureBefore);
          _startMeasuring(HeartMeasurementContext.beforeMedication);
        },
      ),
      secondaries: [
        _EasyAction(
          label: '뒤로',
          icon: Icons.arrow_back_rounded,
          onPressed: _back,
        ),
      ],
    );
  }

  /// 78 · 82 · 재는 중.
  Widget _measuring({
    required EasyDoseStep step,
    required String lead,
    required EasyDoseStep next,
  }) {
    final sensor = _sensor;
    final elapsed = sensor?.elapsedSeconds ?? 0;
    final remaining = (_measureSeconds - elapsed).clamp(0, _measureSeconds);
    final lost =
        sensor != null &&
        (sensor.status == HeartSensorStatus.disconnected ||
            sensor.status == HeartSensorStatus.failed);

    return _EasyStepPage(
      step: step,
      lead: lead,
      title: '재고 있어요',
      body: [
        Center(child: _MeasureRing(seconds: remaining)),
        const SizedBox(height: 22),
        Center(
          child: Text(
            lost ? '센서를 가슴에 다시 대주세요' : '움직이지 말고 가만히 계세요',
            textAlign: TextAlign.center,
            style: AppText.label(
              size: 20,
              color: lost ? AppColors.danger : AppColors.textBody,
            ),
          ),
        ),
      ],
      secondaries: [
        _EasyAction(
          label: '그만 재기',
          icon: Icons.close_rounded,
          onPressed: () => _stopMeasuring(next),
        ),
      ],
    );
  }

  /// 79 · 먹기 전 잘 쟀어요.
  Widget _beforeDone() {
    return _EasyStepPage(
      step: EasyDoseStep.beforeDone,
      lead: '먹기 전 심박',
      title: '잘 쟀어요',
      body: [
        SeniorCard(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '먹기 전',
                style: AppText.label(size: 18, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${_before ?? '–'}', style: AppText.hero(size: 64)),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '회',
                      style: AppText.cardTitle(
                        size: 22,
                        color: AppColors.textBody,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      primary: _EasyAction(
        label: '이제 약 드시기',
        icon: Icons.medication_rounded,
        onPressed: () => _goTo(EasyDoseStep.take),
      ),
      secondaries: [
        _EasyAction(
          label: '뒤로',
          icon: Icons.arrow_back_rounded,
          onPressed: _back,
        ),
      ],
    );
  }

  /// 80 · 이 약을 드세요.
  Widget _take(DoseEntry dose) {
    return _EasyStepPage(
      step: EasyDoseStep.take,
      lead: '이 약을 드시고',
      title: '복약 완료하셨나요?',
      body: [_MedicineCard(medicines: dose.medicines)],
      primary: _EasyAction(
        label: '먹었어요',
        icon: Icons.check_rounded,
        onPressed: () => unawaited(_record(dose.slot)),
      ),
      secondaries: [
        _EasyAction(
          label: '뒤로',
          icon: Icons.arrow_back_rounded,
          onPressed: _back,
        ),
      ],
    );
  }

  /// 81 · 한 번 더 재요.
  Widget _afterAsk() {
    final slot = _recordedSlot;
    return _EasyStepPage(
      step: EasyDoseStep.afterAsk,
      lead: '잘하셨어요',
      title: '한 번 더 재요',
      body: [
        SeniorCard(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 34,
                color: AppColors.point,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      slot == null ? '약 기록했어요' : '${slot.label} 약 기록했어요',
                      style: AppText.label(
                        size: 20,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('센서는 그대로 차고 계세요', style: AppText.body(size: 20)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      primary: _EasyAction(
        label: '복약 후 심박 측정',
        icon: Icons.favorite_rounded,
        onPressed: () {
          _goTo(EasyDoseStep.measureAfter);
          _startMeasuring(HeartMeasurementContext.afterMedication);
        },
      ),
      secondaries: [
        _EasyAction(
          label: '뒤로',
          icon: Icons.arrow_back_rounded,
          onPressed: _back,
        ),
        _EasyAction(
          label: '안 잴래요',
          icon: Icons.skip_next_rounded,
          onPressed: () => _goTo(EasyDoseStep.allDone),
        ),
      ],
    );
  }

  /// 83 · 84 · 결과.
  Widget _result(TodayMedication today) {
    final before = _before;
    final after = _after;
    // 둘 중 하나라도 없으면 비교하지 않는다.
    if (before == null || after == null) return _allDone(today);

    // 100회를 넘으면 빠른 쪽으로 말한다. 그 아래는 평소와 비슷하다고 본다.
    final fast = after > 100;

    return _EasyStepPage(
      step: EasyDoseStep.result,
      lead: fast ? '고장이 아니에요' : '심박수가',
      title: fast ? '조금 빨라요' : '평소와 비슷해요',
      body: [
        SeniorCard(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: _ResultValue(
                  label: '먹기 전',
                  value: before,
                  labelColor: AppColors.textSecondary,
                  valueColor: AppColors.textTertiary,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 32,
                  color: AppColors.strongLine,
                ),
              ),
              Expanded(
                child: _ResultValue(
                  label: '먹은 후',
                  value: after,
                  labelColor: fast ? AppColors.danger : AppColors.point,
                  valueColor: fast ? AppColors.danger : AppColors.point,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!fast)
          SeniorCard(
            radius: 26,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Text(
              '약이 잘 듣고 있어요',
              style: AppText.label(size: 19, color: AppColors.textPrimary),
            ),
          )
        else ...[
          const _NumberedCard(
            lines: ['의자에 앉아 쉬세요', '물 한 잔 드세요', '10분 뒤에 다시 재요'],
          ),
          // 가족이 등록돼 있을 때만 알렸다고 말한다.
          if (today.hasGuardian) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.send_rounded, size: 24, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${today.guardianTitle}께 자동으로 알렸어요',
                      style: AppText.label(size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
      primary: _EasyAction(
        label: fast ? '알겠어요' : '기록 끝내기',
        icon: Icons.check_rounded,
        onPressed: () => _goTo(EasyDoseStep.allDone),
      ),
      secondaries: fast
          ? const []
          : [
              _EasyAction(
                label: '뒤로',
                icon: Icons.arrow_back_rounded,
                onPressed: _back,
              ),
            ],
    );
  }

  /// 아직 오늘 약을 못 읽었을 때. 첫 걸음도 결과도 말하지 않는다.
  Widget _waiting(MedicationFetchStatus status) {
    final loading = status == MedicationFetchStatus.loading;
    return _EasyStepPage(
      lead: '오늘 약을',
      title: loading ? '불러오는 중이에요' : '불러오지 못했어요',
      body: [
        SeniorCard(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Text(
            loading ? '잠시만 기다려 주세요.' : '인터넷 연결을 확인하고 다시 눌러 보세요.',
            style: AppText.body(size: 19),
          ),
        ),
      ],
      primary: loading
          ? null
          : _EasyAction(
              label: '다시 불러오기',
              icon: Icons.refresh_rounded,
              onPressed: () => unawaited(
                ref.read(medicationProvider.notifier).refreshFromServer(),
              ),
            ),
    );
  }

  /// 85 · 오늘 다 했어요.
  Widget _allDone(TodayMedication today) {
    final alarm = ref.watch(alarmPreferencesProvider);
    final firstHour = alarm.ringingHours.isEmpty
        ? null
        : alarm.ringingHours.first;

    return _EasyStepPage(
      lead: '오늘 약을',
      title: '다 드셨어요',
      body: [
        SeniorCard(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '오늘 먹은 약',
                style: AppText.cardTitle(
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < today.doses.length; i++) ...[
                      if (i > 0) const SizedBox(width: 9),
                      Expanded(child: _DoneSlotBox(dose: today.doses[i])),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (firstHour != null) ...[
          const SizedBox(height: 12),
          SeniorCard(
            radius: 26,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.alarm_rounded,
                  size: 30,
                  color: AppColors.point,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '내일 ${AlarmPreferences.clock(firstHour)}에 알려드려요',
                    style: AppText.label(
                      size: 19,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        _MoreGrid(
          items: [
            _MoreItem(
              icon: Icons.medication_rounded,
              label: '내 약',
              onTap: widget.onOpenMedicines,
            ),
            _MoreItem(
              icon: Icons.calendar_month_rounded,
              label: '복약 기록',
              onTap: widget.onOpenRecord,
            ),
            _MoreItem(
              icon: Icons.favorite_rounded,
              label: '심박수',
              onTap: widget.onOpenHeart,
            ),
            _MoreItem(
              icon: Icons.person_rounded,
              label: '내 정보',
              onTap: widget.onOpenMyInfo,
            ),
            _MoreItem(
              icon: Icons.support_agent_rounded,
              label: '약사에게 묻기',
              onTap: widget.onOpenChat,
            ),
            _MoreItem(
              icon: Icons.undo_rounded,
              label: '복약 전으로 되돌리기',
              onTap: _recordedSlot == null ? null : _undoRecord,
            ),
          ],
        ),
      ],
    );
  }
}

/// 걸음 하나의 틀 — 걸음 표시 · 제목 · 본문 · 아래 버튼.
class _EasyStepPage extends StatelessWidget {
  /// 걸음 번호를 매길 단계. 없으면 걸음 표시를 그리지 않는다 (85).
  final EasyDoseStep? step;

  final String lead;
  final String title;
  final String? subtitle;
  final List<Widget> body;
  final _EasyAction? primary;
  final List<_EasyAction> secondaries;

  const _EasyStepPage({
    this.step,
    required this.lead,
    required this.title,
    this.subtitle,
    required this.body,
    this.primary,
    this.secondaries = const [],
  });

  @override
  Widget build(BuildContext context) {
    final number = step == null ? null : easyStepNumber(step!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (number != null) ...[
                  _StepPips(current: number),
                  const SizedBox(height: 18),
                ],
                Text(
                  lead,
                  style: AppText.screenTitle(
                    size: 28,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
                Text(title, style: AppText.screenTitle(size: 28)),
                if (subtitle case final String note) ...[
                  const SizedBox(height: 8),
                  Text(note, style: AppText.body(size: 19)),
                ],
                const SizedBox(height: 18),
                ...body,
              ],
            ),
          ),
        ),
        // 아래 버튼은 스크롤과 함께 밀리지 않는다. 늘 같은 자리에 있어야
        // 다음에 무엇을 누를지 찾지 않는다.
        if (primary != null || secondaries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (primary case final _EasyAction action) ...[
                  SeniorButton(
                    label: action.label,
                    icon: action.icon,
                    minHeight: 76,
                    fontSize: 24,
                    radius: 18,
                    elevated: true,
                    onPressed: action.onPressed,
                  ),
                  if (secondaries.isNotEmpty) const SizedBox(height: 12),
                ],
                if (secondaries.isNotEmpty)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < secondaries.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: SeniorButton(
                              label: secondaries[i].label,
                              icon: secondaries[i].icon,
                              kind: SeniorButtonKind.card,
                              minHeight: 62,
                              fontSize: 20,
                              radius: 18,
                              onPressed: secondaries[i].onPressed,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 버튼 하나에 필요한 것.
class _EasyAction {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _EasyAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
}

/// 여덟 걸음 표시 (명세서 76~84).
class _StepPips extends StatelessWidget {
  /// 1부터 센 지금 걸음.
  final int current;

  const _StepPips({required this.current});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$kEasyDoseSteps걸음 중 $current걸음째',
      child: ExcludeSemantics(
        child: Row(
          children: [
            // 막대는 한 줄로 잇고, 안쪽 채움만 걸음만큼 찬다.
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 8,
                  color: AppColors.stepTrack,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: current / kEasyDoseSteps,
                    child: const ColoredBox(color: AppColors.pointFill),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$current / $kEasyDoseSteps',
              style: AppText.cardTitle(size: 18, color: AppColors.point),
            ),
          ],
        ),
      ),
    );
  }
}

/// 약 칸 (명세서 76·80) — 사진 · 이름과 생김새 · 몇 알.
class _MedicineCard extends StatelessWidget {
  final List<Medicine> medicines;

  const _MedicineCard({required this.medicines});

  @override
  Widget build(BuildContext context) {
    if (medicines.isEmpty) {
      return SeniorCard(
        radius: 26,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Text('약 목록을 아직 받지 못했어요', style: AppText.body(size: 19)),
      );
    }

    return SeniorCard(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < medicines.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _MedicineRow(medicine: medicines[i]),
          ],
        ],
      ),
    );
  }
}

class _MedicineRow extends StatelessWidget {
  final Medicine medicine;

  const _MedicineRow({required this.medicine});

  @override
  Widget build(BuildContext context) {
    final look = medicine.appearance?.trim() ?? '';
    return Row(
      children: [
        PillPhoto(size: 56, imageUrl: medicine.imageUrl),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(medicine.displayName, style: AppText.cardTitle(size: 21)),
              if (look.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(look, style: AppText.body(size: 17)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          medicine.frequencyLabel,
          style: AppText.cardTitle(size: 22, color: AppColors.point),
        ),
      ],
    );
  }
}

/// 번호 붙은 안내 칸 (명세서 77·84).
class _NumberedCard extends StatelessWidget {
  final List<String> lines;

  const _NumberedCard({required this.lines});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.pointFill,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: AppText.cardTitle(size: 18, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    lines[i],
                    style: AppText.label(
                      size: 20,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 재는 동안 남은 시간을 보여 주는 동그라미 (명세서 78·82).
class _MeasureRing extends StatelessWidget {
  final int seconds;

  const _MeasureRing({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$seconds초 남았어요',
      child: ExcludeSemantics(
        child: Container(
          width: 230,
          height: 230,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.pointRing,
            shape: BoxShape.circle,
          ),
          child: Container(
            width: 196,
            height: 196,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  size: 44,
                  color: AppColors.point,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$seconds', style: AppText.bigTime(size: 36)),
                    Text('초', style: AppText.bigTime(size: 36)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 결과 값 한 쪽 (명세서 83·84).
class _ResultValue extends StatelessWidget {
  final String label;
  final int value;
  final Color labelColor;
  final Color valueColor;

  const _ResultValue({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value회',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppText.label(size: 17, color: labelColor)),
            const SizedBox(height: 4),
            Text('$value', style: AppText.hero(size: 48, color: valueColor)),
          ],
        ),
      ),
    );
  }
}

/// 오늘 먹은 약 한 칸 (명세서 85).
class _DoneSlotBox extends StatelessWidget {
  final DoseEntry dose;

  const _DoneSlotBox({required this.dose});

  static String _clock(DateTime time) {
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$hour12:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final taken = dose.taken;
    final empty = dose.medicines.isEmpty;
    final value = empty
        ? '없음'
        : taken
        ? _clock((dose.takenAt ?? DateTime.now()).toLocal())
        : '아직';
    // 드셨으면 ✓, 약이 있는데 안 드셨으면 ✗. 약이 없는 때는 표시하지 않는다.
    final mark = empty
        ? ''
        : taken
        ? '✓'
        : '✗';
    final ink = taken
        ? AppColors.textPrimary
        : empty
        ? AppColors.slotPending
        : AppColors.calendarMissedInk;

    return Semantics(
      label: '${dose.slot.label} $value',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            color: taken
                ? AppColors.pointRing
                : empty
                ? AppColors.sunken
                : AppColors.calendarMissed,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dose.slot.label,
                    style: AppText.label(size: 17, color: AppColors.textBody),
                  ),
                  if (mark.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      mark,
                      style: AppText.cardTitle(
                        size: 17,
                        color: ink,
                      ).copyWith(height: 1),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: AppText.cardTitle(size: 21, color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 85의 "더 보기" 두 칸씩 여섯 칸.
class _MoreItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _MoreItem({required this.icon, required this.label, this.onTap});
}

class _MoreGrid extends StatelessWidget {
  final List<_MoreItem> items;

  const _MoreGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int row = 0; row * 2 < items.length; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _MoreTile(item: items[row * 2])),
                const SizedBox(width: 12),
                if (row * 2 + 1 < items.length)
                  Expanded(child: _MoreTile(item: items[row * 2 + 1]))
                else
                  const Spacer(),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  final _MoreItem item;

  const _MoreTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: item.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: item.onTap,
          child: Opacity(
            opacity: item.onTap == null ? 0.45 : 1,
            child: Container(
              constraints: const BoxConstraints(minHeight: 104),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: kCardShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 38, color: AppColors.textPrimary),
                  const SizedBox(height: 8),
                  Text(
                    item.label,
                    textAlign: TextAlign.center,
                    style: AppText.cardTitle(size: 19),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
