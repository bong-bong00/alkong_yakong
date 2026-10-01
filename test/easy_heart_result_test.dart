import 'package:alkong_yakong/features/easy_flow/presentation/easy_heart_result.dart';
import 'package:alkong_yakong/features/easy_flow/presentation/easy_dose_flow.dart';
import 'package:alkong_yakong/features/medication/application/medication_controller.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:alkong_yakong/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RemainingMedication extends MedicationController {
  @override
  TodayMedication build() => const TodayMedication(
    guardianRelation: '보호자',
    guardianName: '가족',
    doses: [
      DoseEntry(
        slot: DoseSlot.morning,
        medicines: [Medicine(ingredient: '시험약', amount: '1알')],
      ),
      DoseEntry(
        slot: DoseSlot.dinner,
        medicines: [Medicine(ingredient: '시험약', amount: '1알')],
      ),
    ],
  );
  @override
  Future<DoseCheckOutcome> take(DoseSlot slot, {DateTime? now}) async {
    state = state.copyWith(
      doses: [
        for (final dose in state.doses)
          if (dose.slot == slot) dose.copyWith(taken: true) else dose,
      ],
    );
    return DoseCheckOutcome.recorded;
  }
}

void main() {
  Finder readable(String value) => find.byWidgetPredicate(
    (widget) =>
        widget is Text && widget.data?.replaceAll('\u2060', '') == value,
  );
  test('adult resting range boundaries and factual differences', () {
    expect(easyHeartRange(59), '느린 심박수');
    expect(easyHeartRange(60), '정상 심박수');
    expect(easyHeartRange(100), '정상 심박수');
    expect(easyHeartRange(101), '빠른 심박수');
    expect(easyHeartChange(96, 97), '복약 전보다 1회/분 높아요');
    expect(easyHeartChange(97, 96), '복약 전보다 1회/분 낮아요');
    expect(easyHeartChange(96, 96), '복약 전과 같아요');
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'comparison chart has blue after value and no exaggerated axis, scale=$scale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: const EasyHeartResult(before: 96, value: 97),
                ),
              ),
            ),
          ),
        );
        expect(find.text('96회/분'), findsOneWidget);
        expect(find.text('97회/분'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('97회/분')).style!.color,
          AppColors.point,
        );
        expect(readable('정상 심박수'), findsNWidgets(2));
        expect(readable('두 값만으로 약효나 부작용을 판단할 수는 없어요.'), findsOneWidget);
        expect(readable('1회/분 높아요'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
        expect(find.text('약이 잘 듣고 있어요'), findsNothing);
        final bars = tester
            .widgetList<Container>(find.byType(Container))
            .where((item) => item.constraints?.maxWidth == 44)
            .toList();
        expect(bars, hasLength(2));
        expect(
          bars[1].constraints!.maxHeight / bars[0].constraints!.maxHeight,
          closeTo(97 / 96, .001),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final value in [54, 101]) {
    testWidgets(
      'requested paragraphs removed, retaining qualified reference: $value',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: EasyHeartResult(value: value)),
            ),
          ),
        );
        expect(readable(easyHeartRange(value)), findsOneWidget);
        expect(find.textContaining('잠시 쉬고 다시 측정'), findsNothing);
        expect(find.textContaining('119'), findsNothing);
        expect(readable('성인이 쉴 때의 기준이에요.'), findsOneWidget);
        expect(readable('심박수만으로 복약 여부를 판단할 수는 없어요.'), findsNothing);
        expect(find.textContaining('약 복용 가능 여부를 판단'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'narrow comparison keeps Korean endings together $width/$scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: const Padding(
                      padding: EdgeInsets.all(18),
                      child: EasyHeartResult(before: 99, value: 102),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(readable('3회/분 높아요'), findsOneWidget);
          expect(readable('빠른 심박수'), findsOneWidget);
          expect(readable('성인이 쉴 때의 기준이에요.'), findsOneWidget);
          for (final sentence in ['3회/분 높아요', '성인이 쉴 때의 기준이에요.']) {
            final finder = readable(sentence);
            final text = tester.widget<Text>(finder);
            final painter = TextPainter(
              text: TextSpan(text: text.data, style: text.style),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout(maxWidth: tester.getSize(finder).width);
            // No single Korean ending stranded on the last line.
            expect(
              painter.computeLineMetrics().last.width,
              greaterThan(text.style!.fontSize! * scale * 1.2),
            );
            painter.dispose();
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('partial completion never claims all daily medicines taken', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [medicationProvider.overrideWith(_RemainingMedication.new)],
        child: const MaterialApp(home: Scaffold(body: EasyDoseFlow())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('측정 안 할래요'));
    await tester.pumpAndSettle();
    expect(find.text('5 / 8'), findsOneWidget);
    await tester.tap(find.text('먹었어요'));
    await tester.pumpAndSettle();
    expect(find.text('이번 복약을'), findsOneWidget);
    expect(find.text('기록했어요'), findsOneWidget);
    expect(find.text('다 드셨어요'), findsNothing);
  });

  testWidgets('wear step uses real illustration, keeping step 2 actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [medicationProvider.overrideWith(_RemainingMedication.new)],
        child: const MaterialApp(home: Scaffold(body: EasyDoseFlow())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('복약 전 심박 측정'));
    await tester.pumpAndSettle();
    expect(find.byType(EasySensorWearIllustration), findsOneWidget);
    expect(find.text('차는 모습 그림 자리'), findsNothing);
    expect(find.text('2 / 8'), findsOneWidget);
    expect(find.text('다 착용했어요'), findsOneWidget);
    expect(find.text('뒤로'), findsOneWidget);
  });
}
