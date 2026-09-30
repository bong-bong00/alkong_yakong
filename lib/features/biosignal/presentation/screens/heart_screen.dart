import 'dart:async';

import 'package:flutter/material.dart';
import '../../../medication/application/medication_controller.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/domain/medication_models.dart';
import '../../application/heart_sensor.dart';
import '../../data/heart_repository.dart';
import '../../domain/heart_data.dart';
import '../widgets/heart_readings_card.dart';
import 'measure_screen.dart';
import 'monthly_heart_screen.dart';
import 'polar_screen.dart';

/// 24 · 심박수 관리.
///
/// **폴라 센서로 복약 전·후 두 번만 잰다.** 연속 선 그래프는 쓰지 않는다.
///
/// 이 화면은 **서버에서 읽어 온 기록만** 그린다. 읽는 중이면 읽는 중,
/// 못 읽었으면 못 읽었다, 기록이 없으면 없다고 말한다. 예시 숫자로
/// 빈자리를 채우면 어르신도 보호자도 그 숫자를 진짜로 읽는다.
class HeartScreen extends StatefulWidget {
  final String guardianTitle;

  /// 누구의 기록을 볼지. null이면 로그인한 사람(MvpSession) 본인이다.
  /// 보호자가 어르신 기록을 볼 때 어르신 id를 넘긴다.
  final String? userId;

  /// 기록을 읽어 올 곳. 없으면 이 화면이 하나 만들어 쓴다.
  final HeartRepository? repository;

  /// 지금 붙어 있는 센서. 배터리와 연결 상태가 여기서 온다.
  /// 없으면 이 화면은 센서를 붙잡지 않는다 — 목록만 보는 화면이기 때문이다.
  final HeartSensor? sensor;

  /// 앱의 /biosignal route에서 열렸을 때 측정 화면도 GoRouter 경로로 연다.
  /// EasyFlow 등 화면을 직접 포함하는 기존 진입점은 false로 두어 기존
  /// Navigator 동작을 유지한다.
  final bool routeBasedMeasurement;

  const HeartScreen({
    super.key,
    this.guardianTitle = '',
    this.userId,
    this.repository,
    this.sensor,
    this.routeBasedMeasurement = false,
  });

  @override
  State<HeartScreen> createState() => _HeartScreenState();
}

class _HeartScreenState extends State<HeartScreen> {
  late final HeartRepository _repository =
      widget.repository ?? HeartRepository();

  /// 서버에서 읽어 온 기록. 아직 못 읽었으면 null — 예시로 채우지 않는다.
  HeartData? _data;
  bool _loading = true;

  /// 몇 번째 물음인지. 늦게 온 답은 버린다.
  int _requestId = 0;

  /// 뒤에서 다시 읽다 실패했는지. 보이는 기록은 그대로 두되 말은 해 준다.
  bool _reloadFailed = false;
  bool _failed = false;

  /// 보호자 알림 스위치. 기록이 아니라 설정이라 기록과 따로 든다.
  bool _notifyGuardian = true;
  HeartMeasurementContext _measurementContext = HeartMeasurementContext.general;

  /// 다른 사람(어르신)의 기록을 보는 중인지. 그러면 이 전화기로 재지 않는다.
  bool get _viewingOther => widget.userId != null;

  @override
  void initState() {
    super.initState();
    widget.sensor?.addListener(_onSensor);
    unawaited(_load());
  }

  /// 측정 화면이 열리고 닫히는 동안에도 센서는 계속 알려 온다.
  /// 그리는 도중에 setState 를 부르면 터지므로 한 박자 뒤로 미룬다.
  bool _sensorUpdatePending = false;

  void _onSensor() {
    if (_sensorUpdatePending) return;
    _sensorUpdatePending = true;
    scheduleMicrotask(() {
      _sensorUpdatePending = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.sensor?.removeListener(_onSensor);
    super.dispose();
  }

  /// 기록을 읽는다.
  ///
  /// [quiet]이면 들고 있던 기록을 치우지 않고 뒤에서 새로 읽는다 —
  /// 재고 돌아왔을 때 화면이 한 번 비었다 채워지면 어르신이 놀란다.
  Future<void> _load({bool quiet = false}) async {
    // 처음 부를 때는 이미 "읽는 중"으로 시작하므로 initState 안에서
    // setState 를 부르지 않는다. 다시 불러오기를 누른 경우에만 상태를 되돌린다.
    if (!quiet && !_loading) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final id = ++_requestId;
    final loaded = await _repository.fetch(userId: widget.userId);
    if (!mounted || id != _requestId) return;
    setState(() {
      _loading = false;
      if (loaded != null) {
        _data = loaded;
        _failed = false;
        _reloadFailed = false;
      } else if (!quiet || _data == null) {
        _failed = true;
      } else {
        // 조용히 다시 읽다 실패했으면 보이는 기록은 그대로 두고,
        // 못 읽었다는 말만 덧붙인다.
        _reloadFailed = true;
      }
    });
  }

  Future<void> _openMonthly() async {
    // 한 달을 열 때마다 서버에서 다시 읽는다. 못 읽으면 옛 기록으로
    // 한 달 화면을 열지 않고, 이 화면에서 못 읽었다고 말한다.
    await _load(quiet: true);
    if (!mounted) return;
    final data = _data;
    // 다시 읽기가 실패했으면 옛 기록으로 한 달 화면을 열지 않는다.
    if (data == null || _failed || _reloadFailed) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MonthlyHeartScreen(
          data: data,
          guardianTitle: resolveGuardianTitle(context, widget.guardianTitle),
        ),
      ),
    );
    // 돌아오면 그 사이 올라간 기록을 다시 읽는다.
    if (mounted) await _load(quiet: true);
  }

  Future<void> _openMeasure() async {
    final measurementContext = _measurementContext;
    setState(() => _measurementContext = HeartMeasurementContext.general);
    final guardianTitle = resolveGuardianTitle(context, widget.guardianTitle);
    final saved =
        widget.routeBasedMeasurement && GoRouter.maybeOf(context) != null
        ? await context.push<bool>(
            '/biosignal/measure',
            extra: HeartMeasureRouteArgs(
              guardianTitle: guardianTitle,
              sensor: widget.sensor,
              measurementContext: measurementContext,
              onSaved: () => _load(quiet: true),
            ),
          )
        : await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => MeasureScreen(
                guardianTitle: guardianTitle,
                sensor: widget.sensor,
                measurementContext: measurementContext,
                returnToPreviousScreen: true,
              ),
            ),
          );
    // 저장 완료 화면이 성공을 확인해 준 경우에만 최신 서버 기록을 읽는다.
    // 취소·연결 실패·저장 실패는 성공 기록처럼 갱신하지 않는다.
    if (saved == true && mounted) unawaited(_load(quiet: true));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          SeniorHeader(
            background: AppColors.pageBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SeniorBackButton(
                      onTap: widget.routeBasedMeasurement
                          ? () => context.go('/')
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '오늘 ',
                              style: AppText.screenTitle(
                                size: 24,
                              ).copyWith(fontWeight: FontWeight.w500),
                            ),
                            TextSpan(
                              text: '심박수',
                              style: AppText.screenTitle(size: 24),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SeniorSegmented(
                  labels: const ['이번 주', '한 달'],
                  index: 0,
                  onChanged: (i) {
                    // 어느 쪽을 눌러도 서버에서 다시 읽는다. 한 달은
                    // 새로 읽은 기록으로 연다.
                    if (i == 1) {
                      unawaited(_openMonthly());
                    } else {
                      unawaited(_load(quiet: true));
                    }
                  },
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
                  if (_loading && data == null)
                    const _LoadingCard()
                  else if (_failed && data == null)
                    _FailedCard(onRetry: () => unawaited(_load()))
                  else if (data != null && !data.hasReadings)
                    _EmptyCard(viewingOther: _viewingOther)
                  else if (data != null)
                    _TodayCard(data: data),
                  if ((_failed || _reloadFailed) && data != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '심박수 기록을 불러오지 못했어요',
                      style: AppText.body(size: 18, color: AppColors.danger),
                    ),
                  ],
                  if (data != null) ...[
                    if (data.readingsFor(monthly: false).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      HeartReadingsCard(
                        readings: data.readingsFor(monthly: false),
                        hasComparison: data.today.isComplete,
                      ),
                    ],
                  ],
                  if (!_viewingOther) ...[
                    const SizedBox(height: 16),
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('측정 목적', style: AppText.cardTitle(size: 20)),
                          const SizedBox(height: 12),
                          SeniorSegmented(
                            labels: HeartMeasurementContext.values
                                .map((context) => context.label)
                                .toList(growable: false),
                            index: HeartMeasurementContext.values.indexOf(
                              _measurementContext,
                            ),
                            onChanged: (index) => setState(
                              () => _measurementContext =
                                  HeartMeasurementContext.values[index],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SeniorButton(
                      label: '지금 재기',
                      icon: Icons.favorite_rounded,
                      minHeight: 72,
                      fontSize: 23,
                      onPressed: () => unawaited(_openMeasure()),
                    ),
                  ],
                  const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_viewingOther) ...[
                          Expanded(
                            child: _SensorTile(
                              sensor: widget.sensor,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PolarScreen(sensor: widget.sensor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: _NotifyTile(
                            guardianTitle: resolveGuardianTitle(
                              context,
                              widget.guardianTitle,
                            ),
                            value: _notifyGuardian,
                            onChanged: (v) =>
                                setState(() => _notifyGuardian = v),
                          ),
                        ),
                      ],
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

/// 기록을 읽는 동안. 숫자 자리에 아무것도 미리 두지 않는다.
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: AppColors.point,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '심박수 기록을 불러오고 있어요',
            textAlign: TextAlign.center,
            style: AppText.cardTitle(size: 19),
          ),
        ],
      ),
    );
  }
}

/// 기록을 못 읽었을 때. 무엇이 안 됐는지와 다시 하는 길을 같이 둔다.
class _FailedCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _FailedCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(
                child: Icon(
                  TablerIcons.cloud_off,
                  size: 28,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '심박수 기록을 불러오지 못했어요',
                  style: AppText.cardTitle(size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '인터넷이 연결되어 있는지 확인한 뒤 다시 눌러 주세요. '
            '측정해 둔 기록은 지워지지 않았어요.',
            style: AppText.body(size: 18),
          ),
          const SizedBox(height: 16),
          SeniorButton(
            label: '다시 불러오기',
            icon: TablerIcons.refresh,
            kind: SeniorButtonKind.secondary,
            minHeight: 62,
            fontSize: 21,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// 읽기는 됐는데 잰 기록이 하나도 없을 때.
class _EmptyCard extends StatelessWidget {
  /// 보호자가 어르신 기록을 보는 중이면 "재 보세요"라고 권하지 않는다.
  final bool viewingOther;
  const _EmptyCard({required this.viewingOther});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.sunken,
              shape: BoxShape.circle,
            ),
            child: const ExcludeSemantics(
              child: Icon(
                TablerIcons.heartbeat,
                size: 38,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '아직 측정 기록이 없어요',
            textAlign: TextAlign.center,
            style: AppText.cardTitle(size: 21),
          ),
          const SizedBox(height: 6),
          Text(
            viewingOther
                ? '센서로 측정하고 나면 여기에 약 먹기 전·후 값이 남아요.'
                : '약 드시기 전과 드신 뒤에 한 번씩 재면\n여기에 남아요.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 오늘 잰 것 — 전·후 두 값을 나란히.
class _TodayCard extends StatelessWidget {
  final HeartData data;
  const _TodayCard({required this.data});

  /// 잰 쪽 시각만 잇는다. 둘 다 없으면 이 줄을 그리지 않는다.
  String? _measuredLine() {
    final parts = [
      if (data.today.before != null && data.beforeAt.isNotEmpty) data.beforeAt,
      if (data.today.after != null && data.afterAt.isNotEmpty) data.afterAt,
    ];
    return parts.isEmpty ? null : '${parts.join(' · ')}에 쟀어요';
  }

  @override
  Widget build(BuildContext context) {
    final today = data.today;
    final generalReadings = data.todayReadings
        .where(
          (reading) =>
              reading.measurementContext == HeartMeasurementContext.general,
        )
        .toList(growable: false);
    final hasMedicationReading = today.before != null || today.after != null;
    final measuredToday = hasMedicationReading || generalReadings.isNotEmpty;
    final drop = today.drop;
    final measuredLine = _measuredLine();

    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 오늘 잰 것이 없으면 "저녁 약"이라고 붙일 근거도 없다.
          if (hasMedicationReading && data.todaySlotLabel.isNotEmpty) ...[
            Text(
              data.todaySlotLabel,
              style: AppText.label(size: 17, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
          ],
          if (!measuredToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.sunken,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '오늘은 아직 재지 않았어요',
                style: AppText.label(size: 18.5, color: AppColors.textPrimary),
              ),
            )
          else if (hasMedicationReading)
            Row(
              children: [
                Expanded(
                  child: _ValueBox(
                    label: '먹기 전',
                    value: today.before,
                    labelColor: AppColors.textSecondary,
                    valueColor: AppColors.heartBefore,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: ExcludeSemantics(
                    child: Icon(
                      TablerIcons.arrow_right,
                      size: 34,
                      color: AppColors.strongLine,
                    ),
                  ),
                ),
                Expanded(
                  child: _ValueBox(
                    label: '먹은 후',
                    value: today.after,
                    labelColor: AppColors.point,
                    valueColor: AppColors.point,
                  ),
                ),
              ],
            ),
          for (final reading in generalReadings) ...[
            if (hasMedicationReading || reading != generalReadings.first)
              const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.sunken,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reading.measurementContext.label,
                          style: AppText.label(
                            size: 17,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${reading.bpm}회/분',
                          style: AppText.emphasis(size: 24),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    DoseSlot.absoluteTime(reading.measuredAt.toLocal()),
                    style: AppText.caption(size: 16),
                  ),
                ],
              ),
            ),
          ],
          if (drop != null) ...[
            const SizedBox(height: 16),
            const SeniorDivider(),
            const SizedBox(height: 14),
            Text(
              _summaryLine(drop, today.after),
              style: AppText.label(
                size: 19,
                color: AppColors.textPrimary,
                weight: FontWeight.w700,
              ),
            ),
          ],
          if (measuredLine != null) ...[
            const SizedBox(height: 10),
            Text(measuredLine, style: AppText.caption(size: 17)),
          ],
        ],
      ),
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String label;
  final int? value;
  final Color labelColor;
  final Color valueColor;

  const _ValueBox({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: value == null ? '$label 재지 못했어요' : '$label $value회',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppText.label(size: 17, color: labelColor)),
            const SizedBox(height: 4),
            Text(
              value?.toString() ?? '–',
              style: AppText.hero(size: 52, color: valueColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// 심박수 한 줄 요약 (명세서 52).
///
/// "정상 범위예요"는 먹은 후 값이 60~100일 때만 붙인다.
/// 범위를 벗어난 값에 정상이라고 말하면 안심할 근거를 지어내는 것이다.
String _summaryLine(int drop, int? after) {
  final change = drop > 0
      ? '$drop회 낮아졌어요'
      : drop < 0
      ? '${-drop}회 높아졌어요'
      : '먹기 전과 같은 수치예요';
  final inRange = after != null && after >= 60 && after <= 100;
  return inRange ? '$change · 정상 범위예요' : change;
}

/// 심박 센서 칸 (명세서 52). 네모 한 칸에 이름과 상태만 둔다.
///
/// 연결 여부·배터리는 **센서가 말한 것만** 쓴다. 이 화면이 센서를
/// 넘겨받지 않았으면 연결됐는지 모르므로 "끊김"이라고도 하지 않는다.
class _SensorTile extends StatelessWidget {
  final HeartSensor? sensor;
  final VoidCallback onTap;

  const _SensorTile({required this.sensor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sensor = this.sensor;
    final connected = sensor?.status == HeartSensorStatus.streaming;
    final String state;
    if (sensor == null) {
      state = '눌러서 연결하기';
    } else if (connected) {
      state = sensor.battery == null ? '연결됨' : '연결됨 · ${sensor.battery}%';
    } else {
      state = '연결 안 됨';
    }

    return SeniorCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('심박 센서', style: AppText.cardTitle(size: 19)),
            const SizedBox(height: 4),
            Text(
              state,
              style: AppText.label(
                size: 17,
                color: connected ? AppColors.point : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 심박수가 빠르면 보호자에게 알리는 칸 (명세서 52).
/// 칸 전체가 켜고 끄는 단추다 — 작은 스위치보다 짚기 쉽다.
class _NotifyTile extends StatelessWidget {
  final String guardianTitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotifyTile({
    required this.guardianTitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      button: true,
      label: '심박수가 빠를 때 $guardianTitle에게 알리기',
      child: ExcludeSemantics(
        child: SeniorCard(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          onTap: () => onChanged(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 90),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  value
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  size: 32,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 10),
                Text('빠르면 가족에게', style: AppText.cardTitle(size: 19)),
                const SizedBox(height: 4),
                Text(
                  value ? '알림 켜짐' : '알림 꺼짐',
                  style: AppText.label(
                    size: 17,
                    color: value ? AppColors.point : AppColors.textTertiary,
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

/// 아직 저장된 기록을 읽어오지 못했을 때.
///
/// 화면은 그대로 보여주되 **이 숫자가 무엇인지** 먼저 밝힌다.
/// 예시를 진짜 기록으로 읽고 나면 그것대로 판단의 근거가 된다.
