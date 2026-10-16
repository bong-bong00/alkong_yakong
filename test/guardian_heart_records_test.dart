import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/biosignal/data/heart_repository.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/screens/monthly_heart_screen.dart';
import 'package:alkong_yakong/features/biosignal/presentation/widgets/heart_readings_card.dart';
import 'package:alkong_yakong/features/dashboard/application/medication_history_provider.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/guardian_home_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_data.dart';
import 'package:alkong_yakong/features/medication/application/medication_controller.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() => MvpSession.userId = 'guardian-id');

  Map<String, dynamic> payload({bool empty = false}) => {
    'period_date': '2026-10-13',
    'today': {},
    'week': [],
    'month': [],
    'readings': [
      if (!empty)
        for (var id = 1; id <= 4; id++)
          {
            'id': id,
            'bpm': 70 + id,
            'measured_at': DateTime(
              2026,
              10,
              13,
              10,
              id,
            ).toUtc().toIso8601String(),
            'measurement_context': id == 1
                ? 'before_medication'
                : id == 2
                ? 'after_medication'
                : 'general',
          },
    ],
  };

  Widget wrap(Widget child) => ProviderScope(
    overrides: [
      patientTodayProvider.overrideWith(
        (ref, id) async => TodayMedication.empty,
      ),
      patientHistoryProvider.overrideWith((ref, id) async => const {}),
    ],
    child: MaterialApp(theme: AppTheme.build(), home: child),
  );

  testWidgets(
    'guardian opens selected patient week/month records without measuring',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requests = <http.Request>[];
      final repository = HeartRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(jsonEncode(payload()), 200);
          }),
        ),
      );
      await tester.pumpWidget(
        wrap(
          GuardianStatusScreen(
            patient: const CarePatient(
              linkId: 'linked',
              patientId: 'patient-id',
              name: '김복자',
              heartRate: 114,
            ),
            position: 1,
            total: 1,
            heartRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('114 bpm'), findsOneWidget);
      expect(
        tester.getCenter(find.text('114 bpm')).dy,
        closeTo(tester.getCenter(find.text('최근 심박수')).dy, 1),
      );
      await tester.tap(find.byKey(const Key('guardian-open-heart-records')));
      await tester.pumpAndSettle();
      expect(find.byType(HeartScreen), findsOneWidget);
      expect(find.text('김복자 님'), findsOneWidget);
      expect(find.textContaining('기록 조회'), findsNothing);
      final refresh = tester.widget<TextButton>(
        find.byKey(const Key('guardian-heart-refresh')),
      );
      expect(refresh.style!.textStyle!.resolve({})!.fontSize, 15);
      expect(
        tester.getSize(find.byKey(const Key('guardian-heart-refresh'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(find.text('측정 목적'), findsNothing);
      expect(find.text('연결 확인 후 측정'), findsNothing);
      expect(find.byType(HeartDailyBars), findsOneWidget);
      expect(
        tester.widget<HeartDailyBars>(find.byType(HeartDailyBars)).weekStart,
        DateTime(2026, 10, 12),
      );
      expect(
        tester
            .widget<HeartReadingsCard>(find.byType(HeartReadingsCard))
            .readings
            .map((r) => r.id),
        [4, 3],
      );
      final toggle = find.byKey(const Key('weekly-heart-toggle-readings'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<HeartReadingsCard>(find.byType(HeartReadingsCard))
            .readings
            .length,
        4,
      );
      await tester.tap(find.text('한 달'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthlyHeartScreen), findsOneWidget);
      expect(find.text('김복자 님'), findsOneWidget);
      expect(
        tester
            .widget<HeartReadingsCard>(find.byType(HeartReadingsCard))
            .readings
            .length,
        2,
      );
      final monthlyToggle = find.byKey(
        const Key('monthly-heart-toggle-readings'),
      );
      await tester.ensureVisible(monthlyToggle);
      await tester.tap(monthlyToggle);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<HeartReadingsCard>(find.byType(HeartReadingsCard))
            .readings
            .length,
        4,
      );
      expect(
        requests.every(
          (r) =>
              r.method == 'GET' &&
              r.url.path == '/api/v1/users/patient-id/biosignal/heart-summary',
        ),
        isTrue,
      );
      expect(MvpSession.userId, 'guardian-id');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty and failed patient queries are distinct; retry stays on same patient',
    (tester) async {
      var status = 503;
      final paths = <String>[];
      final repo = HeartRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(jsonEncode(payload(empty: true)), status);
          }),
        ),
      );
      await tester.pumpWidget(
        wrap(
          HeartScreen(
            userId: 'patient-two',
            patientTitle: '다른 환자',
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('심박수 기록을 불러오지 못했어요'), findsOneWidget);
      status = 200;
      await tester.tap(find.byKey(const Key('guardian-heart-refresh')));
      await tester.pumpAndSettle();
      expect(find.text('아직 측정 기록이 없어요'), findsOneWidget);
      expect(find.text('연결 확인 후 측정'), findsNothing);
      expect(paths.toSet(), {
        '/api/v1/users/patient-two/biosignal/heart-summary',
      });
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 360.0]) {
    testWidgets('guardian heart header fits at $width with large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = HeartRepository(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(jsonEncode(payload()), 200),
          ),
        ),
      );
      await tester.pumpWidget(
        wrap(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: HeartScreen(
              userId: 'patient',
              patientTitle: '어머니 · 김복자',
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('어머니 · 김복자 님'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('한 달'));
      await tester.pumpAndSettle();
      expect(find.text('어머니 · 김복자 님'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'weekly chart preserves cross-month dates and ignores general readings',
    (tester) async {
      final source = <Map<String, dynamic>>[
        for (final date in [DateTime(2026, 12, 31), DateTime(2027, 1, 1)])
          {
            'id': date.day,
            'bpm': 75,
            'measured_at': date
                .add(const Duration(hours: 12))
                .toUtc()
                .toIso8601String(),
            'measurement_context': 'before_medication',
          },
        {
          'id': 99,
          'bpm': 125,
          'measured_at': DateTime(2027, 1, 2, 12).toUtc().toIso8601String(),
          'measurement_context': 'general',
        },
      ];
      final repo = HeartRepository(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                ...payload(),
                'period_date': '2027-01-03',
                'readings': source,
              }),
              200,
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        wrap(HeartScreen(userId: 'patient', repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('단위: 회/분 · 잰 날 2일'), findsOneWidget);
      expect(
        tester.widget<HeartDailyBars>(find.byType(HeartDailyBars)).weekStart,
        DateTime(2026, 12, 28),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing patient ID cannot open guardian own heart records', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const GuardianStatusScreen(
          patient: CarePatient(linkId: '', patientId: '', name: '환자'),
          position: 1,
          total: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guardian-open-heart-records')), findsNothing);
  });
}
