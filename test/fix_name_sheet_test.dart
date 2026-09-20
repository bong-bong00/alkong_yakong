import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/prescription/presentation/widgets/fix_name_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 09 · 약 이름 고치기 시트.
///
/// 시트는 화면 위에 덮이는 창이라, 화면 쪽 스낵바를 띄우면 시트 뒤에 가려
/// 아무것도 보이지 않는다. 시트가 자기 스낵바 자리를 갖는지 여기서 지킨다.
void main() {
  Widget host() => MaterialApp(
    theme: AppTheme.build(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: GestureDetector(
            onTap: () => showFixNameSheet(context, current: '메트포르민 500mg'),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );

  testWidgets('이름을 비우고 누르면 시트 위에 스낵바로 알린다', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('이 이름으로 고치기'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('약 이름을 적어 주세요.'), findsOneWidget);
    // 시트는 닫히지 않고 그대로 있다.
    expect(find.text('약 이름 고치기'), findsOneWidget);
  });

  testWidgets('이름을 고치면 그 이름을 돌려준다', (tester) async {
    String? returned;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () async {
                  returned = await showFixNameSheet(context, current: '메트포르민');
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '아스피린장용정');
    await tester.tap(find.text('이 이름으로 고치기'));
    await tester.pumpAndSettle();

    expect(returned, '아스피린장용정');
  });
}
