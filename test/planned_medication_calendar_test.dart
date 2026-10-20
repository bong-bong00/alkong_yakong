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
        final ring = find.byKey(const ValueKey('month-selected-ring-15'));
        expect(tester.getSize(ring), const Size(46, 46));
        expect(
          find.byKey(const ValueKey('month-planned-dot-16')),
          findsNothing,
        );
        expect(
          tester.getRect(dot).bottom,
          lessThan(tester.getRect(find.text('15')).top),
        );
        expect(
          tester.getRect(find.text('15')).top - tester.getRect(dot).bottom,
          lessThanOrEqualTo(4),
        );
        final legend = find.byKey(const ValueKey('calendar-legend-row'));
        final markers = find.descendant(
          of: legend,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).shape == BoxShape.circle,
          ),
        );
        expect(markers, findsNWidgets(4));
        final markerSizes = [
          for (final marker in markers.evaluate())
            tester.getSize(find.byWidget(marker.widget)),
        ];
        for (final size in markerSizes) {
          expect(size, markerSizes.first);
        }
        expect(tester.getSize(dot), const Size(6, 6));
        final labels = ['복약 완료', '미완료', '오늘', '예정'];
        final labelRects = [
          for (final label in labels)
            tester.getRect(
              find.descendant(of: legend, matching: find.text(label)),
            ),
        ];
        for (final rect in labelRects) {
          expect(rect.center.dy, closeTo(labelRects.first.center.dy, 1));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
        }
        expect(find.text('다 드심'), findsNothing);
        expect(find.text('놓침'), findsNothing);
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

  testWidgets('weekly dates do not display planned markers', (tester) async {
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
    expect(dot, findsNothing);
    expect(find.text('${future.day}'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('복약 예정')), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'long names and amounts have aligned separate columns at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const names = [
          '휴온스시메티딘정200밀리그램(수출명:TAGAMENTTab.200밀리그램)',
          '프리마란정(메퀴타진)',
          '아디팜정(히드록시진염산염)',
        ];
        await tester.pumpWidget(
          wrap(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SingleChildScrollView(
                child: PlannedMedicationDetail(
                  dayLabel: '10월 22일',
                  slots: [
                    PlannedMedicationSlot(
                      slot: '아침',
                      time: '08:00',
                      medicines: [
                        for (final name in names) PlannedMedicine(name, '0.5알'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final amounts = [
          for (final name in names)
            tester.getRect(find.byKey(ValueKey('planned-amount-08:00-$name'))),
        ];
        for (var i = 0; i < names.length; i++) {
          final nameRect = tester.getRect(find.text(names[i]));
          expect(amounts[i].left - nameRect.right, greaterThanOrEqualTo(23));
          expect(amounts[i].top, closeTo(nameRect.top, 1));
          expect(amounts[i].right, closeTo(amounts.first.right, 1));
          if (i > 0) {
            expect(
              nameRect.top - tester.getRect(find.text(names[i - 1])).bottom,
              greaterThanOrEqualTo(15),
            );
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

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
