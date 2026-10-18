import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/medicine_arrived_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final sender in ['', '가족', '보호자', '김이박']) {
    testWidgets('처방전 등록 안내와 보호자 표시: $sender', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: MedicineArrivedScreen(senderTitle: sender),
      ));
      final expected = sender.isEmpty || sender == '가족' ? '보호자' : sender;
      expect(find.text('처방전이 등록되었어요'), findsOneWidget);
      expect(find.text('$expected 님이 처방전을 등록했어요'), findsOneWidget);
      expect(find.text('약이 들어왔어요'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
