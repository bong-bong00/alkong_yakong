import 'package:alkong_yakong/features/dur_analysis/presentation/screens/dur_analysis_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('충돌 약 카드에는 이름만 보이고 효과 설명은 보이지 않는다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: DurAnalysisScreen(
            initialResult: {
              'assessment_status': 'RISK_FOUND',
              'matches': [
                {
                  'type': '병용금기',
                  'medicine_names_a': ['아디팜정(히드록시진염산염)'],
                  'medicine_names_b': ['코다론정(아미오다론염산염)'],
                  'easy_line_a': '아디팜정은 가려움 완화에 사용해요.',
                  'easy_line_b': '코다론정은 심장 박동을 조절해요.',
                  'why_easy': '함께 먹으면 주의가 필요해요.',
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('아디팜정'), findsWidgets);
    expect(find.text('코다론정'), findsOneWidget);
    expect(find.textContaining('가려움 완화에 사용해요'), findsNothing);
    expect(find.textContaining('심장 박동을 조절해요'), findsNothing);
    expect(find.text('함께 먹으면 주의가 필요해요.'), findsOneWidget);
  });
}
