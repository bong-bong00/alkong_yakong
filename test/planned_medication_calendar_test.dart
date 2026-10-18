import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/dashboard/domain/planned_medication.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/month_calendar_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/medication_record_screen.dart';
import 'package:alkong_yakong/features/dashboard/presentation/widgets/planned_medication_detail.dart';
import 'package:alkong_yakong/features/dashboard/application/medication_calendar_provider.dart';
import 'package:alkong_yakong/features/dashboard/application/medication_history_provider.dart';
import 'package:alkong_yakong/features/medication/application/medication_controller.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';

const plans = [
  PlannedMedicationSlot(
    slot: '아침',
    time: '08:15',
    medicines: [
      PlannedMedicine('등록약 A', '0.5정'),
      PlannedMedicine('등록약 B', '5mL'),
    ],
  ),
];

void main() {
  final now = DateTime.now();
  final month = DateTime(now.year, now.month + 1, 15);
  Widget wrap(Widget child) => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(body: child),
    ),
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'calendar preserves existing layout, dots above dates, readonly plans at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          wrap(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: MonthCalendarScreen(
                year: month.year,
                month: month.month,
                initialDay: 15,
                days: [
                  const CalendarDay(15, DayMark.future, plannedSlots: plans),
                  const CalendarDay(16, DayMark.future),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('전체 달력'), findsOneWidget);
        final dot = find.byKey(const ValueKey('month-planned-dot-15'));
        expect(dot, findsOneWidget);
        expect(
          find.byKey(const ValueKey('month-planned-dot-16')),
          findsNothing,
        );
        expect(
          tester.getRect(dot).bottom,
          lessThan(tester.getRect(find.text('15')).top),
        );
        await tester.ensureVisible(find.byType(PlannedMedicationDetail));
        await tester.pumpAndSettle();
        expect(find.text('복약 예정 1회'), findsOneWidget);
        expect(find.text('08:15'), findsOneWidget);
        expect(find.text('등록약 A'), findsOneWidget);
        expect(find.text('0.5정'), findsOneWidget);
        expect(find.text('5mL'), findsOneWidget);
        expect(find.text('먹었어요'), findsNothing);
        expect(find.text('미복용'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('16'));
        await tester.tap(find.text('16'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(PlannedMedicationDetail));
        expect(find.text('복약 일정이 없어요'), findsOneWidget);
        expect(find.text('등록약 A'), findsNothing);
      },
    );
  }

  testWidgets('weekly marker sits above number without marking completed', (
    tester,
  ) async {
    final future = DateTime(now.year, now.month, now.day + 1);
    await tester.pumpWidget(
      wrap(
        AdherenceWeekCard(
          days: [DayStatus(date: future, taken: 0, total: 2, isFuture: true)],
          onOpenCalendar: () {},
        ),
      ),
    );
    final dot = find.byKey(ValueKey('week-planned-dot-${future.day}'));
    expect(dot, findsOneWidget);
    expect(
      tester.getRect(dot).bottom,
      lessThan(tester.getRect(find.text('${future.day}')).top),
    );
    expect(find.bySemanticsLabel(RegExp('복약 예정')), findsOneWidget);
  });

  testWidgets(
    'record tab selection loads future details rather than past-dose status',
    (tester) async {
      final future = DateTime(now.year, now.month, now.day + 1);
      final requests = <MonthKey>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            medicationProvider.overrideWith(_EmptyPlannedMedication.new),
            medicationHistoryProvider.overrideWith((ref) async => {}),
            medicationMonthPlansProvider.overrideWith((ref, key) async {
              requests.add(key);
              return {future.day: plans};
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.build(),
            home: const Scaffold(body: MedicationRecordScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<AdherenceWeekCard>(find.byType(AdherenceWeekCard))
          .onPickDay!(
        DayStatus(date: future, taken: 0, total: 1, isFuture: true),
      );
      await tester.pumpAndSettle();
      expect(requests.single.year, future.year);
      expect(requests.single.month, future.month);
      expect(find.byType(PlannedMedicationDetail), findsOneWidget);
      expect(find.text('등록약 A'), findsOneWidget);
      expect(find.text('미복용'), findsNothing);
      expect(find.text('먹었어요'), findsNothing);
    },
  );

  for (final patient in [null, 'linked-patient']) {
    testWidgets('calendar requests correct subject: $patient', (tester) async {
      MvpSession.userId = 'signed-in';
      final paths = <String>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            wrap(
              MonthCalendarScreen(
                patientUserId: patient,
                year: month.year,
                month: month.month,
                initialDay: 15,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(paths, [
            '/api/v1/users/${patient ?? 'signed-in'}/medication-calendar',
          ]);
          expect(
            find.byKey(const ValueKey('month-planned-dot-15')),
            findsOneWidget,
          );
          expect(find.text('08:15'), findsOneWidget);
        },
        () => MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'year': month.year,
              'month': month.month,
              'has_schedules': true,
              'days': [
                {
                  'day': 15,
                  'mark': 'future',
                  'planned_slots': [
                    {
                      'slot': '아침',
                      'time': '08:15',
                      'medicines': [
                        {'name': '등록약 A', 'amount': '0.5정'},
                      ],
                    },
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    });
  }

  testWidgets('failed schedule fetch is not shown as an empty plan', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(
        wrap(
          MonthCalendarScreen(
            year: month.year,
            month: month.month,
            initialDay: 15,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('복약 일정을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('복약 일정이 없어요'), findsNothing);
    }, () => MockClient((_) async => http.Response('{}', 503)));
  });

  test(
    'missing/invalid schedule data never fabricates a default dose or time',
    () {
      final result = PlannedMedicationSlot.parse([
        {
          'slot': '아침',
          'time': '25:90',
          'medicines': [{}],
        },
      ]);
      expect(result.single.time, '시간 확인 필요');
      expect(result.single.medicines.single.amount, '복용량 확인 필요');
    },
  );
}

class _EmptyPlannedMedication extends MedicationController {
  @override
  TodayMedication build() => TodayMedication.empty;
}
