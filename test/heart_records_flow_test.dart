import 'dart:async';
import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/core/widgets/senior_card.dart';
import 'package:alkong_yakong/core/widgets/senior_feedback.dart';
import 'package:alkong_yakong/features/biosignal/data/heart_repository.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_data.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_time.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/monthly_heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/saved_screen.dart';
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

http.Response response({int? bpm, int status = 200}) => http.Response(
  jsonEncode(body(bpm: bpm)),
  status,
  headers: {'content-type': 'application/json'},
);

Widget wrap(Widget screen) => ProviderScope(
  child: MaterialApp(theme: AppTheme.build(), home: screen),
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

  testWidgets('monthly count is measured days, not a consecutive or normal claim',
      (tester) async {
    const data = HeartData(
      today: HeartPair(),
      todaySlotLabel: '',
      beforeAt: '',
      afterAt: '',
      week: [],
      month: [
        HeartMonthDay(1, HeartPair(after: 81)),
        HeartMonthDay(3, HeartPair(after: 79)),
      ],
      streakDays: 2,
      bestStreakDays: 2,
      anomaly: null,
      sensorConnected: false,
      sensorBattery: null,
      sensorLastReadAt: '',
      notifyGuardian: false,
    );
    await tester.pumpWidget(wrap(const MonthlyHeartScreen(data: data)));
    await tester.pumpAndSettle();
    expect(find.text('복약 후 심박\n기록이 있어요'), findsOneWidget);
    expect(find.text('일째'), findsNothing);
    expect(find.textContaining('가장 길었던 기록'), findsNothing);
    expect(find.textContaining('정상'), findsNothing);
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
        '오늘 오후 2시 42분',
      );
      expect(
        heartSavedTimeLabel(
          DateTime.parse('2026-05-31T15:00:00Z'),
          now: DateTime.parse('2026-05-31T15:01:00Z'),
          localize: localize,
        ),
        '오늘 오전 12시 0분',
      );
      expect(
        heartSavedTimeLabel(
          DateTime.parse('2026-05-31T14:59:00Z'),
          now: DateTime.parse('2026-05-31T15:01:00Z'),
          localize: localize,
        ),
        '2026년 5월 31일 오후 11시 59분',
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
      expect(find.textContaining('98회/분'), findsOneWidget);
      expect(find.textContaining('비교할 자료는 부족'), findsOneWidget);
      expect(find.text('지난 기록 보기'), findsNothing);
      expect(find.byType(SeniorListRow), findsNothing);
      expect(find.widgetWithText(SeniorSegmented, '이번 주'), findsOneWidget);
      expect(find.widgetWithText(SeniorSegmented, '한 달'), findsOneWidget);
      expect(find.text('지금 측정'), findsOneWidget);
      expect(find.text('폴라 센서'), findsOneWidget);
      expect(find.text('보호자 자동 알림은\n아직 지원하지 않아요'), findsOneWidget);
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
    expect(find.textContaining('98회/분'), findsOneWidget);
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
      await tester.ensureVisible(find.text('지금 측정'));
      await tester.tap(find.text('지금 측정'));
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
      await tester.scrollUntilVisible(find.textContaining('82회/분'), -250);
      expect(find.textContaining('82회/분'), findsOneWidget);
      expect(gets, greaterThanOrEqualTo(2));
      expect(rig.api.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      rig.sensor.dispose();
      await tester.pump();
    },
  );
}
