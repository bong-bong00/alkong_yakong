import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../medication/application/medication_controller.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/polar_pharmacist_ui/constants/app_colors.dart';
import '../../../../core/polar_pharmacist_ui/theme/app_typography.dart';
import '../../../../core/polar_pharmacist_ui/widgets/senior_button.dart';
import '../../../../core/polar_pharmacist_ui/widgets/senior_card.dart';
import '../../../../core/polar_pharmacist_ui/widgets/senior_feedback.dart';
import '../../../../core/polar_pharmacist_ui/widgets/senior_header.dart';
import '../../../medication/domain/medication_models.dart';
import '../../application/heart_device.dart';
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
class HeartScreen extends ConsumerStatefulWidget {
  final String guardianTitle;

  /// 누구의 기록을 볼지. null이면 로그인한 사람(MvpSession) 본인이다.
  /// 보호자가 어르신 기록을 볼 때 어르신 id를 넘긴다.
  final String? userId;

  /// 기록을 읽어 올 곳. 없으면 이 화면이 하나 만들어 쓴다.
  final HeartRepository? repository;

  /// 지금 붙어 있는 센서. 배터리와 연결 상태가 여기서 온다.
  /// 본인 화면에서는 없으면 공유 센서를 쓴다. 타인 기록 조회는 연결하지 않는다.
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
  ConsumerState<HeartScreen> createState() => _HeartScreenState();
}

class _HeartScreenState extends ConsumerState<HeartScreen> {
  bool _showAllWeeklyReadings = false;
  late final HeartSensor? _sensor =
      widget.sensor ??
      (widget.userId == null ? ref.read(heartSensorProvider) : null);
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

  HeartMeasurementContext _measurementContext = HeartMeasurementContext.general;

  /// 다른 사람(어르신)의 기록을 보는 중인지. 그러면 이 전화기로 재지 않는다.
  bool get _viewingOther => widget.userId != null;

  @override
  void initState() {
    super.initState();
    _sensor?.addListener(_onSensor);
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
    _sensor?.removeListener(_onSensor);
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

  /// 센서 화면에서 연결을 확인한 뒤 그대로 재러 간다. 연결되지 않은 채
  /// 나오셨으면 거기서 멈춘다 — 측정 화면을 열어 두면 기다리기만 한다.
  Future<void> _connectThenMeasure() async {
    // 지금 신호가 들어오고 있으면 확인할 것이 없다. 바로 재러 간다.
    if (_streaming) {
      await _openMeasure();
      return;
    }
    final pairedBefore = _paired;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PolarScreen(sensor: _sensor)),
    );
    if (!mounted) return;
    // 연결하고 나오셨을 때만 이어서 재러 간다. 그냥 뒤로 나오셨으면
    // 여기서 멈춘다 — 뒤로가기는 돌아가겠다는 뜻이지 재겠다는 뜻이 아니다.
    if (!_streaming && !(!pairedBefore && _paired)) return;
    await _openMeasure();
  }

  /// 지금 실제로 심박이 들어오는지.
  bool get _streaming => _sensor?.status == HeartSensorStatus.streaming;

  /// 앱이 기억하는 연결 여부. 화면이 센서를 들고 있지 않을 때 쓴다.
  bool get _paired => ProviderScope.containerOf(
    context,
    listen: false,
  ).read(heartDevicePairedProvider);

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
              sensor: _sensor,
              measurementContext: measurementContext,
              onSaved: () => _load(quiet: true),
            ),
          )
        : await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => MeasureScreen(
                guardianTitle: guardianTitle,
                sensor: _sensor,
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
    final weeklyReadings =
        data?.readingsFor(monthly: false) ?? <HeartReading>[];
    weeklyReadings.sort((a, b) {
      final byTime = b.measuredAt.compareTo(a.measuredAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SeniorBackButton(
                      // 쌓여서 열렸으면 그 자리로 돌아가고, 바꿔치워져
                      // 열렸으면(돌아갈 자리가 없으면) 홈으로 간다.
                      onTap: widget.routeBasedMeasurement
                          ? () {
                              final router = GoRouter.maybeOf(context);
                              if (router != null && router.canPop()) {
                                router.pop();
                              } else {
                                context.go('/');
                              }
                            }
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '심박수 관리',
                        style: AppText.screenTitle(size: 24),
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
                    if (weeklyReadings.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      HeartReadingsCard(
                        readings: _showAllWeeklyReadings
                            ? weeklyReadings
                            : weeklyReadings.take(2).toList(growable: false),
                        hasComparison: data.today.isComplete,
                      ),
                      if (weeklyReadings.length > 2)
                        TextButton.icon(
                          key: const Key('weekly-heart-toggle-readings'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.point,
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: () => setState(
                            () => _showAllWeeklyReadings =
                                !_showAllWeeklyReadings,
                          ),
                          icon: Icon(
                            _showAllWeeklyReadings
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                          ),
                          label: Text(
                            _showAllWeeklyReadings ? '접기' : '이전 기록 더 보기',
                            style: AppText.label(size: 18),
                          ),
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
                          _PurposeTray(
                            selected: _measurementContext,
                            onChanged: (value) =>
                                setState(() => _measurementContext = value),
                          ),
                          const SizedBox(height: 16),
                          // 연결부터 확인하고 재러 간다. 차고 계신 줄 알았는데 끜겨 있었던 일이
                          // 제일 잘한다 — 측정 화면에서 기다리기만 하게 두지 않는다.
                          SeniorButton(
                            label: '연결 확인 후 측정',
                            minHeight: 66,
                            fontSize: 23,
                            onPressed: () => unawaited(_connectThenMeasure()),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                : '약 드시기 전과 드신 뒤에 한 번씩 측정하면\n여기에 남아요.',
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

  /// 잰 시각만 짧게. 둘 다 없으면 이 줄을 그리지 않는다.
  ///
  /// "17시 52분 · 18시 40분에 측정했어요"는 숫자를 가린다.
  /// 화살표 하나로 전·후를 잇는다.
  String? _measuredLine() {
    final parts = [
      if (data.today.before != null && data.beforeAt.isNotEmpty) data.beforeAt,
      if (data.today.after != null && data.afterAt.isNotEmpty) data.afterAt,
    ];
    return parts.isEmpty ? null : '측정 ${parts.join(' → ')}';
  }

  @override
  Widget build(BuildContext context) {
    final today = data.today;
    final generalReadings = data.todayReadings
        .where(
          (reading) =>
              reading.measurementContext == HeartMeasurementContext.general,
        )
        .take(2)
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
          Row(
            children: [
              Expanded(child: Text('오늘 측정', style: AppText.cardTitle())),
              // 오늘 잰 것이 없으면 "저녁 약"이라고 붙일 근거도 없다.
              if (hasMedicationReading && data.todaySlotLabel.isNotEmpty)
                // Flexible로 두면 남은 폭을 제목과 반씩 나눠 가져
                // 때 이름이 화면 한가운데로 밀려난다. 폭 상한만 건다.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.45,
                  ),
                  child: Text(
                    data.todaySlotLabel,
                    textAlign: TextAlign.end,
                    style: AppText.label(
                      size: 17,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!measuredToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.sunken,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '오늘은 아직 측정하지 않았어요',
                style: AppText.label(size: 18.5, color: AppColors.textPrimary),
              ),
            )
          else if (hasMedicationReading)
            Row(
              children: [
                Expanded(
                  child: _ValueBox(
                    label: '약 먹기 전',
                    value: today.before,
                    background: AppColors.sunken,
                    labelColor: AppColors.textTertiary,
                    valueColor: AppColors.textPrimary,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: ExcludeSemantics(
                    child: Icon(
                      TablerIcons.arrow_right,
                      size: 30,
                      color: AppColors.point,
                    ),
                  ),
                ),
                Expanded(
                  child: _ValueBox(
                    label: '약 먹은 후',
                    value: today.after,
                    background: AppColors.pointTint,
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
                        const SizedBox(height: 4),
                        _HeartRateRangeLabel(value: reading.bpm),
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.sunken,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      drop > 0
                          ? TablerIcons.trending_down
                          : TablerIcons.trending_up,
                      size: 24,
                      color: AppColors.point,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      drop > 0
                          ? '약 먹은 후 $drop회/분 낮았어요'
                          : drop < 0
                          ? '약 먹은 후 ${-drop}회/분 높았어요'
                          : '약 먹기 전과 같은 수치예요',
                      style: AppText.label(
                        size: 18.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (measuredLine != null) ...[
            const SizedBox(height: 10),
            Text(measuredLine, style: AppText.caption(size: 17)),
          ],
          // 다짐글은 하나만 둔다. 셋을 쌓으면 아무것도 읽지 않는다.
          if (today.before != null && today.after != null) ...[
            const SizedBox(height: 6),
            Text(
              '한 번 비교로 약의 영향을 단정할 수는 없어요.',
              style: AppText.caption(size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String label;
  final int? value;
  final Color background;
  final Color labelColor;
  final Color valueColor;

  const _ValueBox({
    required this.label,
    required this.value,
    required this.background,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final range = value == null ? null : _heartRateRange(value!);
    return Semantics(
      label: value == null ? '$label 측정하지 못했어요' : '$label $value회, $range',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppText.label(size: 17.5, color: labelColor)),
              const SizedBox(height: 6),
              Text(
                value?.toString() ?? '–',
                style: AppText.hero(size: 44, color: valueColor),
              ),
              if (value != null) ...[
                const SizedBox(height: 5),
                _HeartRateRangeLabel(
                  value: value!,
                  color: valueColor,
                  background: AppColors.surface,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeartRateRangeLabel extends StatelessWidget {
  final int value;
  final Color? color;
  final Color? background;

  const _HeartRateRangeLabel({
    required this.value,
    this.color,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? AppColors.pointTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          _heartRateRange(value),
          maxLines: 1,
          softWrap: false,
          style: AppText.caption(
            size: 16,
            color: color ?? AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

String _heartRateRange(int bpm) {
  if (bpm < 60) return '느린 심박수';
  if (bpm <= 100) return '정상 심박수';
  return '빠른 심박수';
}

/// 아직 저장된 기록을 읽어오지 못했을 때.
///
/// 화면은 그대로 보여주되 **이 숫자가 무엇인지** 먼저 밝힌다.
/// 예시를 진짜 기록으로 읽고 나면 그것대로 판단의 근거가 된다.
/// 측정 목적 — 옆에 있는 "약 먹기 전" 칸과 같은 옵은 회색 한 칸 안에서
/// 고른다. 같은 화면에서 같은 뜻의 칸이 서로 다른 회색이면 따로 놓인
/// 것으로 읽힌다.
class _PurposeTray extends StatelessWidget {
  final HeartMeasurementContext selected;
  final ValueChanged<HeartMeasurementContext> onChanged;

  const _PurposeTray({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final values = HeartMeasurementContext.values;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.headerBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (int i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _chip(values[i])),
          ],
        ],
      ),
    );
  }

  Widget _chip(HeartMeasurementContext value) {
    final picked = value == selected;
    return Semantics(
      button: true,
      selected: picked,
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: picked ? AppColors.point : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value.shortLabel,
            textAlign: TextAlign.center,
            style: AppText.cardTitle(
              size: 18.5,
              color: picked ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
