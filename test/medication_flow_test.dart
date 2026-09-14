import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_home_screen.dart';
import 'package:alkong_yakong/features/medication/application/medication_controller.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:alkong_yakong/features/medication/presentation/widgets/dose_guard_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('복약 체크 판정', () {
    late ProviderContainer container;

    setUp(
      () => container = ProviderContainer(
        overrides: [
          medicationProvider.overrideWith(_TestMedicationController.new),
        ],
      ),
    );
    tearDown(() => container.dispose());

    MedicationController controller() =>
        container.read(medicationProvider.notifier);

    test('처음 누르면 기록된다', () {
      final now = DoseSlot.dinner.todayAt(DateTime.now());
      expect(
        controller().take(DoseSlot.dinner, now: now),
        DoseCheckOutcome.recorded,
      );
      expect(
        container.read(medicationProvider).doseOf(DoseSlot.dinner).taken,
        isTrue,
      );
    });

    test('두 번째로 누르면 기록하지 않고 차단한다 (5f)', () {
      final now = DoseSlot.dinner.todayAt(DateTime.now());
      controller().take(DoseSlot.dinner, now: now);
      final takenAt = container
          .read(medicationProvider)
          .doseOf(DoseSlot.dinner)
          .takenAt;

      expect(
        controller().take(DoseSlot.dinner, now: now),
        DoseCheckOutcome.alreadyTaken,
      );
      // 기록 시각이 덮어써지지 않는다.
      expect(
        container.read(medicationProvider).doseOf(DoseSlot.dinner).takenAt,
        takenAt,
      );
    });

    test('4시간 넘게 지나면 바로 기록하지 않는다', () {
      final late = DoseSlot.dinner
          .todayAt(DateTime.now())
          .add(const Duration(hours: 5));
      expect(
        controller().take(DoseSlot.dinner, now: late),
        DoseCheckOutcome.tooLate,
      );
      expect(
        container.read(medicationProvider).doseOf(DoseSlot.dinner).taken,
        isFalse,
      );

      // "그래도 먹었어요"를 고르면 그때 기록된다.
      controller().takeAnyway(DoseSlot.dinner, now: late);
      expect(
        container.read(medicationProvider).doseOf(DoseSlot.dinner).taken,
        isTrue,
      );
    });

    test('되돌리면 기록과 보호자 알림이 함께 취소된다 (4b)', () {
      final now = DoseSlot.dinner.todayAt(DateTime.now());
      controller().take(DoseSlot.dinner, now: now);
      expect(controller().guardianNotifiedFor(DoseSlot.dinner), isTrue);

      controller().undo(DoseSlot.dinner);
      final dose = container.read(medicationProvider).doseOf(DoseSlot.dinner);
      expect(dose.taken, isFalse);
      expect(dose.takenAt, isNull);
      expect(controller().guardianNotifiedFor(DoseSlot.dinner), isFalse);
    });

    test('30분 뒤에 다시를 누르면 그 시각이 남는다', () {
      final now = DoseSlot.dinner.todayAt(DateTime.now());
      final until = controller().snooze(DoseSlot.dinner, now: now);
      expect(until, now.add(const Duration(minutes: 30)));
    });
  });

  testWidgets('중복 복용 차단 시트는 기록 시각을 절대시간으로 보여준다 (5f)', (tester) async {
    var undone = false;
    final dose = DoseEntry(
      slot: DoseSlot.dinner,
      medicines: const [Medicine(ingredient: '메트포르민 500mg', amount: '1알')],
      taken: true,
      takenAt: DateTime(2026, 8, 20, 18, 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDuplicateDoseSheet(
                  context: context,
                  dose: dose,
                  onUndo: () => undone = true,
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('저녁 약은 이미\n드신 것으로 되어 있어요'), findsOneWidget);
    expect(find.text('오후 6시 2분에 기록'), findsOneWidget);

    // 기본 동작은 아무것도 하지 않고 닫기.
    await tester.tap(find.text('알겠어요'));
    await tester.pumpAndSettle();
    expect(undone, isFalse);
    expect(find.text('알겠어요'), findsNothing);
  });

  testWidgets('약 상세에서 돌아오면 오늘 홈의 스크롤 위치가 유지된다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          medicationProvider.overrideWith(_TestMedicationController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: Builder(
            builder: (context) => Scaffold(
              body: PatientHomeScreen(
                onOpenDrug: (_) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('약 상세')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final scrollFinder = find.byType(SingleChildScrollView);
    await tester.drag(scrollFinder, const Offset(0, -100));
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.text('테스트정'));
    await tester.pumpAndSettle();
    expect(find.text('약 상세'), findsOneWidget);

    Navigator.of(tester.element(find.text('약 상세'))).pop();
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    expect(after, before);
  });
}

class _TestMedicationController extends MedicationController {
  @override
  TodayMedication build() {
    return const TodayMedication(
      doses: [
        DoseEntry(
          slot: DoseSlot.dinner,
          medicines: [Medicine(ingredient: '테스트정', amount: '1알')],
        ),
      ],
      guardianRelation: '가족',
      guardianName: '테스트',
      heartRate: 72,
      heartRateNormal: true,
    );
  }
}
