import 'dart:async';
import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/core/polar_pharmacist_ui/widgets/senior_button.dart';
import 'package:alkong_yakong/core/polar_pharmacist_ui/widgets/senior_card.dart';
import 'package:alkong_yakong/core/polar_pharmacist_ui/widgets/senior_feedback.dart';
import 'package:alkong_yakong/core/polar_pharmacist_ui/widgets/senior_header.dart';
import 'package:alkong_yakong/features/biosignal/data/heart_repository.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_data.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_time.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/measure_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/monthly_heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/polar_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/saved_screen.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'polar_save_flow_test.dart' show Rig;

Map<String, dynamic> body({int? bpm}) {
  final now = DateTime.now();
  return {
    'today': {},
    'week': [],
    'month': [],
    'period_date':
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    'readings': [
      if (bpm != null)
        {'id': 1, 'bpm': bpm, 'measured_at': now.toUtc().toIso8601String()},
    ],
  };
}

Map<String, dynamic> bodyWithReading({
  required int bpm,
  required String measuredAt,
  String? measurementContext,
  String? periodDate,
}) {
  final parsed = DateTime.parse(measuredAt).toLocal();
  final reading = <String, dynamic>{
    'id': 1,
    'bpm': bpm,
    'measured_at': measuredAt,
  };
  if (measurementContext != null) {
    reading['measurement_context'] = measurementContext;
  }
  return {
    'today': {},
    'week': [],
    'month': [],
    'period_date':
        periodDate ??
        '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}',
    'readings': [reading],
  };
}

http.Response response({int? bpm, int status = 200}) => http.Response(
  jsonEncode(body(bpm: bpm)),
  status,
  headers: {'content-type': 'application/json'},
);

Widget wrap(Widget screen) => ProviderScope(
  child: MaterialApp(theme: AppTheme.build(), home: screen),
);

HeartData monthlyData(
  List<HeartReading> readings, {
  List<HeartMonthDay> month = const [],
}) => HeartData(
  readings: readings,
  periodDate: DateTime(2026, 9, 28),
  today: const HeartPair(),
  todaySlotLabel: '',
  beforeAt: '',
  afterAt: '',
  week: const [],
  month: month,
  streakDays: 0,
  bestStreakDays: 0,
  anomaly: null,
  sensorConnected: false,
  sensorBattery: null,
  sensorLastReadAt: '',
  notifyGuardian: false,
);

GoRouter heartFlowRouter({
  required HeartRepository repository,
  required Rig rig,
  bool directMeasureFromHome = false,
}) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        body: TextButton(
          onPressed: () {
            if (directMeasureFromHome) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MeasureScreen(
                    sensor: rig.sensor,
                    returnToPreviousScreen: true,
                  ),
                ),
              );
              return;
            }
            context.go('/biosignal');
          },
          child: const Text('홈에서 심박수 관리 열기'),
        ),
      ),
    ),
    GoRoute(
      path: '/biosignal',
      builder: (_, _) => HeartScreen(
        repository: repository,
        sensor: rig.sensor,
        routeBasedMeasurement: true,
      ),
      routes: [
        GoRoute(
          path: 'measure',
          builder: (_, state) {
            final args = state.extra! as HeartMeasureRouteArgs;
            return MeasureScreen(
              guardianTitle: args.guardianTitle,
              sensor: args.sensor,
              measurementContext: args.measurementContext,
              onSaved: args.onSaved,
              returnToPreviousScreen: true,
            );
          },
        ),
        GoRoute(
          path: 'saved',
          builder: (_, state) {
            final args = state.extra! as HeartSavedRouteArgs;
            return SavedScreen(
              bpm: args.bpm,
              savedAt: args.savedAt,
              measurementContext: args.measurementContext,
              guardianTitle: args.guardianTitle,
              onConfirmed: args.onSaved,
              returnToPreviousScreen: true,
            );
          },
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('saved confirmation leaves a first-route completion screen', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/saved',
      routes: [
        GoRoute(
          path: '/saved',
          builder: (_, _) =>
              const SavedScreen(bpm: 92, guardianTitle: '합성 보호자'),
        ),
        GoRoute(
          path: '/biosignal',
          builder: (_, _) => const Scaffold(body: Text('심박수 관리로 돌아옴')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.build(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SavedScreen), findsOneWidget);
    await tester.ensureVisible(find.text('확인했어요'));
    await tester.tap(find.text('확인했어요'));
    await tester.pumpAndSettle();
    expect(find.text('심박수 관리로 돌아옴'), findsOneWidget);
    expect(find.byType(SavedScreen), findsNothing);
  });

  testWidgets('monthly keeps the daily chart even with nothing measured', (
    tester,
  ) async {
    final data = monthlyData(const []);
    await tester.pumpWidget(
      wrap(MonthlyHeartScreen(data: data, now: DateTime(2026, 9, 28))),
    );
    await tester.pumpAndSettle();

    // 잰 것이 없어도 자리는 그대로다. 칸이 통째로 사라지면 기록이 없는
    // 것인지 화면이 잘못된 것인지 알 수 없다.
    expect(find.text('날마다 복약 전·후'), findsOneWidget);
    expect(find.text('9월에는 아직 잰 기록이 없어요'), findsOneWidget);
    expect(find.byKey(const Key('daily-heart-bars')), findsOneWidget);
    // 단정하는 말은 어디에도 없다.
    expect(find.textContaining('비슷했어요'), findsNothing);
    expect(find.textContaining('높았어요'), findsNothing);
  });

  testWidgets(
    'monthly without guardian connection shows no shared-view claim or invented name',
    (tester) async {
      final repository = HeartRepository(
        apiClient: ApiClient(
          client: MockClient((_) async => response(bpm: 98)),
        ),
      );
      final data = await repository.fetch(userId: 'synthetic');
      // No medication provider or guardian lookup is needed to render records.
      await tester.pumpWidget(
        MaterialApp(home: MonthlyHeartScreen(data: data!)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('98회/분'), findsOneWidget);
      expect(find.textContaining('같이 보고 있어요'), findsNothing);
      expect(find.textContaining('김이박'), findsNothing);
    },
  );

  testWidgets('daily chart counts only explicit before/after readings', (
    tester,
  ) async {
    // 일반 측정은 복약 전·후가 아니다. 시각으로 짐작해 넣지 않는다.
    final data = monthlyData(
      [HeartReading(id: 1, bpm: 90, measuredAt: DateTime(2026, 9, 8, 9))],
      month: const [HeartMonthDay(8, HeartPair(before: 90, after: 89))],
    );

    await tester.pumpWidget(
      wrap(MonthlyHeartScreen(data: data, now: DateTime(2026, 9, 28))),
    );
    await tester.pumpAndSettle();

    expect(find.text('9월에는 아직 잰 기록이 없어요'), findsOneWidget);
    expect(find.text('주별 평균'), findsNothing);
  });

  testWidgets('daily chart shows the day it was measured', (tester) async {
    final data = monthlyData([
      HeartReading(
        id: 1,
        bpm: 90,
        measuredAt: DateTime(2026, 9, 8, 9),
        measurementContext: HeartMeasurementContext.beforeMedication,
      ),
      HeartReading(
        id: 2,
        bpm: 91,
        measuredAt: DateTime(2026, 9, 8, 10),
        measurementContext: HeartMeasurementContext.afterMedication,
      ),
    ]);

    await tester.pumpWidget(
      wrap(MonthlyHeartScreen(data: data, now: DateTime(2026, 9, 28))),
    );
    await tester.pumpAndSettle();

    expect(find.text('날마다 복약 전·후'), findsOneWidget);
    expect(find.text('단위: 회/분 · 잰 날 1일'), findsOneWidget);
    expect(find.text('복약 전'), findsWidgets);
    expect(find.text('복약 후'), findsWidgets);
    // 약 때문이라고 단정하지 않는다.
    expect(find.textContaining('비슷했어요'), findsNothing);
    expect(find.textContaining('효과'), findsNothing);
    expect(find.textContaining('약 때문에'), findsNothing);
  });

  testWidgets('daily chart fits narrow screens with large text', (
    tester,
  ) async {
    final data = monthlyData([
      HeartReading(
        id: 1,
        bpm: 90,
        measuredAt: DateTime(2026, 9, 1, 9),
        measurementContext: HeartMeasurementContext.beforeMedication,
      ),
      HeartReading(
        id: 2,
        bpm: 88,
        measuredAt: DateTime(2026, 9, 1, 10),
        measurementContext: HeartMeasurementContext.afterMedication,
      ),
      HeartReading(
        id: 3,
        bpm: 92,
        measuredAt: DateTime(2026, 9, 8, 9),
        measurementContext: HeartMeasurementContext.beforeMedication,
      ),
      HeartReading(
        id: 4,
        bpm: 91,
        measuredAt: DateTime(2026, 9, 8, 10),
        measurementContext: HeartMeasurementContext.afterMedication,
      ),
    ]);

    for (final width in <double>[320, 360]) {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: wrap(
            MonthlyHeartScreen(data: data, now: DateTime(2026, 9, 28)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('날마다 복약 전·후'), findsOneWidget);
      expect(find.text('단위: 회/분 · 잰 날 2일'), findsOneWidget);
      expect(find.textContaining('비슷했어요'), findsNothing);
      expect(find.textContaining('내려갔'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'monthly first record stays below header on narrow large-text screens',
    (tester) async {
      final data = monthlyData([
        HeartReading(id: 1, bpm: 98, measuredAt: DateTime(2026, 9, 22, 14, 42)),
      ]);

      for (final width in <double>[320, 360]) {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: wrap(
              MonthlyHeartScreen(data: data, now: DateTime(2026, 9, 28)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final headerBottom = tester.getBottomLeft(find.byType(SeniorHeader)).dy;
        final recordTop = tester.getTopLeft(find.textContaining('98회/분')).dy;
        expect(recordTop, greaterThanOrEqualTo(headerBottom));
        expect(tester.takeException(), isNull);
      }
    },
  );

  test(
    'UTC 05:42 displays Korean 14:42, preserving midnight/month/week boundary',
    () {
      tzdata.initializeTimeZones();
      final seoul = tz.getLocation('Asia/Seoul');
      DateTime localize(DateTime at) => tz.TZDateTime.from(at, seoul);
      expect(
        heartSavedTimeLabel(
          DateTime.parse('2026-09-18T05:42:00Z'),
          now: DateTime.parse('2026-09-18T06:00:00Z'),
          localize: localize,
        ),
        '오늘 14시 42분',
      );
      expect(
        heartSavedTimeLabel(
          DateTime.parse('2026-05-31T15:00:00Z'),
          now: DateTime.parse('2026-05-31T15:01:00Z'),
          localize: localize,
        ),
        '오늘 0시 0분',
      );
      expect(
        heartSavedTimeLabel(
          DateTime.parse('2026-05-31T14:59:00Z'),
          now: DateTime.parse('2026-05-31T15:01:00Z'),
          localize: localize,
        ),
        '2026년 5월 31일 23시 59분',
      );
    },
  );

  testWidgets(
    'standalone record shown in week/month; tabs refresh with GET only; no sharing claim',
    (tester) async {
      var gets = 0;
      var fail = false;
      final repository = HeartRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            expect(request.method, 'GET');
            gets++;
            return response(bpm: 98, status: fail ? 503 : 200);
          }),
        ),
      );
      await tester.pumpWidget(
        wrap(HeartScreen(repository: repository, guardianTitle: '합성 보호자')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('98회/분'), findsWidgets);
      expect(find.text('평소 심박 측정'), findsWidgets);
      expect(find.textContaining('비교할 자료는 부족'), findsNothing);
      expect(find.text('지난 기록 보기'), findsNothing);
      expect(find.widgetWithText(SeniorSegmented, '이번 주'), findsOneWidget);
      expect(find.widgetWithText(SeniorSegmented, '한 달'), findsOneWidget);
      // 연결과 측정은 단추 하나다. 따로 단 폴라 센서 칸은 없다.
      expect(find.text('연결 확인 후 측정'), findsOneWidget);
      expect(find.text('폴라 센서'), findsNothing);
      expect(find.textContaining('에게 바로 알려요'), findsNothing);
      expect(gets, 1);
      await tester.tap(find.text('한 달'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthlyHeartScreen), findsOneWidget);
      expect(find.textContaining('98회/분'), findsOneWidget);
      expect(find.textContaining('같이 보고 있어요'), findsNothing);
      expect(gets, 2);
      await tester.tap(find.text('이번 주'));
      await tester.pumpAndSettle();
      expect(gets, 3);
      fail = true;
      await tester.tap(find.text('한 달'));
      await tester.pumpAndSettle();
      expect(find.text('심박수 기록을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('아직 측정 기록이 없어요'), findsNothing);
      expect(find.textContaining('같이 보고 있어요'), findsNothing);
    },
  );

  testWidgets(
    'today card shows a general reading with value, local time, and purpose',
    (tester) async {
      final now = DateTime.now();
      final measuredAt = DateTime(now.year, now.month, now.day, 14, 42);
      final repository = HeartRepository(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(
                bodyWithReading(
                  bpm: 92,
                  measuredAt: measuredAt.toUtc().toIso8601String(),
                  measurementContext: 'general',
                ),
              ),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );

      await tester.pumpWidget(wrap(HeartScreen(repository: repository)));
      await tester.pumpAndSettle();

      final todayCard = find.ancestor(
        of: find.text('오늘 측정'),
        matching: find.byType(SeniorCard),
      );
      expect(
        find.descendant(of: todayCard, matching: find.text('92회/분')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: todayCard, matching: find.text('평소 심박 측정')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: todayCard, matching: find.text('일반 범위')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: todayCard,
          matching: find.text(DoseSlot.absoluteTime(measuredAt)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: todayCard, matching: find.text('오늘은 아직 측정하지 않았어요')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'today medication comparison shows ranges, difference, and caveat',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final repository = HeartRepository(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'today': {'before': 54, 'after': 64},
                'today_slot_label': '복약',
                'before_at': '16:00',
                'after_at': '16:01',
                'week': [],
                'month': [],
                'period_date':
                    '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                'readings': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: wrap(HeartScreen(repository: repository)),
        ),
      );
      await tester.pumpAndSettle();

      final todayCard = find.ancestor(
        of: find.text('오늘 측정'),
        matching: find.byType(SeniorCard),
      );
      expect(
        find.descendant(of: todayCard, matching: find.text('느린 범위')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: todayCard, matching: find.text('일반 범위')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: todayCard,
          matching: find.text('약 먹은 후 10회/분 높았어요'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: todayCard,
          matching: find.text('한 번 비교로 약의 영향을 단정할 수는 없어요.'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy reading without measurement context appears as a usual heart reading',
    (tester) async {
      final now = DateTime.now();
      final measuredAt = DateTime(now.year, now.month, now.day, 9, 5);
      final repository = HeartRepository(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(
                bodyWithReading(
                  bpm: 74,
                  measuredAt: measuredAt.toUtc().toIso8601String(),
                ),
              ),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );

      await tester.pumpWidget(wrap(HeartScreen(repository: repository)));
      await tester.pumpAndSettle();

      expect(find.text('평소 심박 측정'), findsWidgets);
      // 오늘 칸과 저장된 기록 줄에 같은 숫자가 한 번씩 적힌다.
      expect(find.text('74회/분'), findsWidgets);
      expect(find.text('오늘은 아직 측정하지 않았어요'), findsNothing);
    },
  );

  testWidgets('outdated response cannot replace newer query', (tester) async {
    final pending = <Completer<http.Response>>[];
    final repository = HeartRepository(
      apiClient: ApiClient(
        client: MockClient((request) {
          final result = Completer<http.Response>();
          pending.add(result);
          return result.future;
        }),
      ),
    );
    await tester.pumpWidget(
      wrap(HeartScreen(repository: repository, guardianTitle: '합성 보호자')),
    );
    await tester.pump();
    await tester.tap(find.text('이번 주'));
    await tester.pump();
    expect(pending.length, 2);
    pending[1].complete(response(bpm: 98));
    await tester.pumpAndSettle();
    pending[0].complete(response(bpm: 71));
    await tester.pumpAndSettle();
    expect(find.textContaining('98회/분'), findsWidgets);
    expect(find.textContaining('71회/분'), findsNothing);
  });

  testWidgets(
    'saved measurement return reloads server records without another POST',
    (tester) async {
      final rig = Rig();
      await rig.sensor.start(measure: false);
      var gets = 0;
      var stored = false;
      final repository = HeartRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            expect(request.method, 'GET');
            gets++;
            return response(bpm: stored ? 82 : null);
          }),
        ),
      );
      await tester.pumpWidget(
        wrap(
          HeartScreen(
            repository: repository,
            sensor: rig.sensor,
            guardianTitle: '합성 보호자',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('아직 측정 기록이 없어요'), findsOneWidget);
      await tester.ensureVisible(find.text('연결 확인 후 측정'));
      await tester.tap(find.text('연결 확인 후 측정'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await rig.widgetWindow(tester);
      stored = true;
      rig.api.succeed(0);
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('저장된 기록 확인하기'));
      await tester.tap(find.text('저장된 기록 확인하기'));
      await tester.pumpAndSettle();
      expect(find.byType(SavedScreen), findsOneWidget);
      await tester.ensureVisible(find.text('확인했어요'));
      await tester.tap(find.text('확인했어요'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('82회/분').first, -250);
      // 오늘 칸과 저장된 기록 줄에 같은 숫자가 한 번씩 적힌다.
      expect(find.text('82회/분'), findsWidgets);
      expect(gets, greaterThanOrEqualTo(2));
      expect(rig.api.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      rig.sensor.dispose();
      await tester.pump();
    },
  );

  for (final purpose in HeartMeasurementContext.values) {
    testWidgets(
      'real GoRouter flow returns ${purpose.value} measurement to heart screen',
      (tester) async {
        final rig = Rig();
        await rig.sensor.start(measure: false);
        var stored = false;
        var gets = 0;
        final measuredAt = DateTime.now();
        final repository = HeartRepository(
          apiClient: ApiClient(
            client: MockClient((request) async {
              expect(request.method, 'GET');
              gets++;
              if (!stored) return response();
              final payload = bodyWithReading(
                bpm: 82,
                measuredAt: measuredAt.toUtc().toIso8601String(),
                measurementContext: purpose.value,
              );
              if (purpose == HeartMeasurementContext.beforeMedication) {
                payload['today'] = {'before': 82};
                payload['before_at'] = '10:30';
              } else if (purpose == HeartMeasurementContext.afterMedication) {
                payload['today'] = {'after': 82};
                payload['after_at'] = '10:30';
              }
              return http.Response(
                jsonEncode(payload),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        );
        final router = heartFlowRouter(repository: repository, rig: rig);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              theme: AppTheme.build(),
              routerConfig: router,
            ),
          ),
        );
        await tester.tap(find.text('홈에서 심박수 관리 열기'));
        await tester.pumpAndSettle();
        if (purpose != HeartMeasurementContext.general) {
          // 고르는 칸은 짧은 이름으로 선다.
          await tester.ensureVisible(find.text(purpose.shortLabel));
          await tester.tap(find.text(purpose.shortLabel));
        }
        await tester.ensureVisible(find.text('연결 확인 후 측정'));
        await tester.tap(find.text('연결 확인 후 측정'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await rig.widgetWindow(tester);
        stored = true;
        rig.api.succeed(0);
        await tester.pump();
        await tester.pump();
        await tester.ensureVisible(find.text('저장된 기록 확인하기'));
        await tester.tap(find.text('저장된 기록 확인하기'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('확인했어요'));
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.path, '/biosignal');
        expect(find.text('홈에서 심박수 관리 열기'), findsNothing);
        expect(find.byType(HeartScreen), findsOneWidget);
        expect(find.byType(SavedScreen), findsNothing);
        final readingsCard = find.ancestor(
          of: find.text('저장된 심박 기록'),
          matching: find.byType(SeniorCard),
        );
        expect(
          find.descendant(
            of: readingsCard,
            matching: find.textContaining('82회/분'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: readingsCard, matching: find.text(purpose.label)),
          findsOneWidget,
        );
        expect(gets, 2);
        expect(rig.api.requests, hasLength(1));

        await tester.pumpWidget(const SizedBox());
        rig.sensor.dispose();
        await tester.pump();
      },
    );
  }

  for (final saveFailure in <({String label, bool rejected})>[
    (label: '기록을 저장하지 못했어요', rejected: true),
    (label: '저장 여부를 확인하지 못했어요', rejected: false),
  ]) {
    testWidgets(
      'real GoRouter keeps ${saveFailure.label} out of success navigation',
      (tester) async {
        final rig = Rig();
        await rig.sensor.start(measure: false);
        final repository = HeartRepository(
          apiClient: ApiClient(client: MockClient((_) async => response())),
        );
        final router = heartFlowRouter(repository: repository, rig: rig);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              theme: AppTheme.build(),
              routerConfig: router,
            ),
          ),
        );
        await tester.tap(find.text('홈에서 심박수 관리 열기'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('연결 확인 후 측정'));
        await tester.tap(find.text('연결 확인 후 측정'));
        await tester.pump(const Duration(milliseconds: 400));
        await rig.widgetWindow(tester);
        if (saveFailure.rejected) {
          rig.api.pending.single.completeError(
            const ApiException('synthetic rejection', statusCode: 400),
          );
        } else {
          rig.api.pending.single.complete(null);
        }
        await tester.pump();
        await tester.pump();

        expect(find.text(saveFailure.label), findsOneWidget);
        expect(find.byType(SavedScreen), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/biosignal');
        await tester.ensureVisible(find.text('그만두기'));
        await tester.tap(find.text('그만두기'));
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.path, '/biosignal');
        expect(find.byType(HeartScreen), findsOneWidget);
        expect(find.byType(MeasureScreen), findsNothing);
        expect(find.textContaining('82회/분'), findsNothing);

        await tester.pumpWidget(const SizedBox());
        rig.sensor.dispose();
        await tester.pump();
      },
    );
  }

  testWidgets(
    'direct home measurement also finishes on refreshed heart screen',
    (tester) async {
      final rig = Rig();
      await rig.sensor.start(measure: false);
      var stored = false;
      var gets = 0;
      final repository = HeartRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            expect(request.method, 'GET');
            gets++;
            return response(bpm: stored ? 82 : null);
          }),
        ),
      );
      final router = heartFlowRouter(
        repository: repository,
        rig: rig,
        directMeasureFromHome: true,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.build(),
            routerConfig: router,
          ),
        ),
      );
      await tester.tap(find.text('홈에서 심박수 관리 열기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MeasureScreen), findsOneWidget);
      await rig.widgetWindow(tester);
      stored = true;
      rig.api.succeed(0);
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('저장된 기록 확인하기'));
      await tester.tap(find.text('저장된 기록 확인하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인했어요'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/biosignal');
      expect(find.byType(HeartScreen), findsOneWidget);
      expect(find.byType(MeasureScreen), findsNothing);
      expect(find.byType(SavedScreen), findsNothing);
      await tester.scrollUntilVisible(find.text('82회/분').first, -250);
      // 오늘 칸과 저장된 기록 줄에 같은 숫자가 한 번씩 적힌다.
      expect(find.text('82회/분'), findsWidgets);
      expect(gets, greaterThanOrEqualTo(1));
      expect(rig.api.requests, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      rig.sensor.dispose();
      await tester.pump();
    },
  );

  for (final useBack in [false, true]) {
    testWidgets(
      'Polar search measurement exits with back=$useBack under GoRouter',
      (tester) async {
        final rig = Rig();
        final router = GoRouter(
          initialLocation: '/biosignal',
          routes: [
            GoRoute(
              path: '/biosignal',
              builder: (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PolarScreen(sensor: rig.sensor),
                    ),
                  ),
                  child: const Text('센서 화면 열기'),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)),
        );
        await tester.tap(find.text('센서 화면 열기'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('기기 찾기'));
        await tester.tap(find.text('기기 찾기'));
        await tester.pumpAndSettle();
        expect(rig.sdk.searches, 1);
        await tester.ensureVisible(find.text('지금 측정'));
        await tester.tap(find.text('지금 측정'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        rig.sdk.sample(62);
        await tester.pump();
        expect(find.byType(MeasureScreen), findsOneWidget);
        if (useBack) {
          await tester.tap(
            find.descendant(
              of: find.byType(MeasureScreen),
              matching: find.byType(SeniorBackButton),
            ),
          );
        } else {
          await tester.ensureVisible(find.text('그만두기'));
          await tester.tap(find.text('그만두기'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(MeasureScreen), findsNothing);
        expect(find.byType(PolarScreen), findsOneWidget);
        expect(rig.sensor.measuring, isFalse);
        expect(rig.api.requests, isEmpty);
        await tester.pump(const Duration(seconds: 50));
        expect(rig.api.requests, isEmpty);
        await tester.pumpWidget(const SizedBox());
        rig.sensor.dispose();
        await tester.pump();
      },
    );
  }

  testWidgets('real GoRouter cancellation returns to heart without saving', (
    tester,
  ) async {
    final rig = Rig();
    await rig.sensor.start(measure: false);
    final repository = HeartRepository(
      apiClient: ApiClient(client: MockClient((_) async => response())),
    );
    final router = heartFlowRouter(repository: repository, rig: rig);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.build(),
          routerConfig: router,
        ),
      ),
    );
    await tester.tap(find.text('홈에서 심박수 관리 열기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('연결 확인 후 측정'));
    await tester.tap(find.text('연결 확인 후 측정'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MeasureScreen), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(MeasureScreen),
        matching: find.byType(SeniorBackButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/biosignal');
    expect(find.byType(HeartScreen), findsOneWidget);
    expect(find.byType(MeasureScreen), findsNothing);
    expect(find.byType(SavedScreen), findsNothing);
    expect(rig.api.requests, isEmpty);

    await tester.pumpWidget(const SizedBox());
    rig.sensor.dispose();
    await tester.pump();
  });

  testWidgets(
    'measurement purpose is selected before start and resets to general',
    (tester) async {
      final rig = Rig();
      await rig.sensor.start(measure: false);
      final repository = HeartRepository(
        apiClient: ApiClient(client: MockClient((_) async => response())),
      );
      await tester.pumpWidget(
        wrap(HeartScreen(repository: repository, sensor: rig.sensor)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('복약 전'));
      await tester.tap(find.text('복약 전'));
      await tester.ensureVisible(find.text('연결 확인 후 측정'));
      final startButton = tester.widget<SeniorButton>(
        find.ancestor(
          of: find.text('연결 확인 후 측정'),
          matching: find.byType(SeniorButton),
        ),
      );
      startButton.onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MeasureScreen), findsOneWidget);
      expect(
        rig.sensor.measurementContext,
        HeartMeasurementContext.beforeMedication,
      );
      expect(
        find.descendant(
          of: find.byType(MeasureScreen),
          matching: find.text('복약 후'),
        ),
        findsNothing,
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      // 목적은 평소로 돌아온다. 고른 칸만 selected로 말한다.
      final picked = tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.text('평소'),
              matching: find.byType(Semantics),
            ),
          )
          .where((node) => node.properties.selected == true);
      expect(picked, isNotEmpty);
      expect(rig.sensor.measurementContext, HeartMeasurementContext.general);
      await tester.pumpWidget(const SizedBox());
      rig.sensor.dispose();
      await tester.pump();
    },
  );

  for (final width in [320.0, 360.0]) {
    testWidgets('measurement purpose fits ${width.toInt()}px at 1.3x text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final repository = HeartRepository(
        apiClient: ApiClient(client: MockClient((_) async => response())),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.build(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: HeartScreen(repository: repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('측정 목적'), -200);
      // 고르는 칸은 짧은 이름으로 한 줄에 선다.
      expect(find.text('평소'), findsOneWidget);
      expect(find.text('복약 전'), findsOneWidget);
      expect(find.text('복약 후'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
