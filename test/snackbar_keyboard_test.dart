import 'package:alkong_yakong/core/widgets/senior_feedback.dart';
import 'package:flutter/material.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/proxy_signup_screen.dart';
import 'package:alkong_yakong/features/auth/presentation/screens/signup_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 스낵바는 자판이 내려가면 **자판이 없을 때 뜨는 자리로 따라 내려와야** 한다.
/// 자판이 있던 허공에 남아 있으면 어르신 눈에는 화면 한가운데 떠 있는 글자다.
void main() {
  testWidgets('자판이 내려가면 스낵바도 따라 내려온다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showSeniorSnackbar(context, '어르신 성함을 적어주세요'),
                child: const Text('띄우기'),
              ),
            ),
          ),
        ),
      ),
    );

    // 자판이 올라온 상태.
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();

    await tester.tap(find.text('띄우기'));
    await tester.pumpAndSettle();

    final withKeyboard = tester.getRect(find.byType(SnackBar)).bottom;
    final screenBottom = tester.getSize(find.byType(MaterialApp)).height;
    // 자판 위에 떠야 한다.
    expect(withKeyboard, lessThan(screenBottom - 200));

    // 자판을 내린다.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    final withoutKeyboard = tester.getRect(find.byType(SnackBar)).bottom;
    expect(
      withoutKeyboard,
      greaterThan(withKeyboard),
      reason: '자판이 내려갔는데 스낵바가 그 자리에 남아 있다',
    );
    expect(
      screenBottom - withoutKeyboard,
      lessThan(80),
      reason: '자판이 없을 때는 화면 아래에 붙어야 한다',
    );
  });

  testWidgets('대리 가입 화면에서도 자판이 내려가면 스낵바가 따라 내려온다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProxySignupScreen())),
    );
    await tester.pumpAndSettle();

    // 자판이 올라온 채로 틀린 곳을 알린다.
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();
    await tester.ensureVisible(find.text('어르신 전화기로 확인번호 보내기'));
    await tester.tap(find.text('어르신 전화기로 확인번호 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('어르신 성함을 적어주세요'), findsOneWidget);
    final withKeyboard = tester.getRect(find.byType(SnackBar)).bottom;

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    final withoutKeyboard = tester.getRect(find.byType(SnackBar)).bottom;

    expect(
      withoutKeyboard,
      greaterThan(withKeyboard),
      reason: '자판이 내려갔는데 스낵바가 그 자리에 남아 있다',
    );
  });

  testWidgets('회원가입 화면에서도 자판이 내려가면 스낵바가 따라 내려온다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SignupScreen())),
    );
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();

    // 역할을 고르지 않고 다음으로 넘어가면 틀린 곳을 알린다.
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    final withKeyboard = tester.getRect(find.byType(SnackBar)).bottom;

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    final withoutKeyboard = tester.getRect(find.byType(SnackBar)).bottom;

    expect(
      withoutKeyboard,
      greaterThan(withKeyboard),
      reason: '자판이 내려갔는데 스낵바가 그 자리에 남아 있다',
    );
  });
}
