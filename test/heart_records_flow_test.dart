import 'dart:async';
import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/biosignal/data/heart_repository.dart';
import 'package:alkong_yakong/features/biosignal/domain/heart_time.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/monthly_heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/saved_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(find.text('아직 잰 기록이 없어요'), findsNothing);
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
      expect(find.text('아직 잰 기록이 없어요'), findsOneWidget);
      await tester.ensureVisible(find.text('지금 재기'));
      await tester.tap(find.text('지금 재기'));
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
