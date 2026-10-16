import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/core/constants/app_colors.dart';
import 'package:alkong_yakong/core/widgets/senior_header.dart';
import 'package:alkong_yakong/core/polar_pharmacist_ui/widgets/senior_header.dart'
    as polar;
import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_data.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/care_family_screen.dart';
import 'package:alkong_yakong/features/guardian/application/guardians_provider.dart';
import 'package:alkong_yakong/features/guardian/application/guardian_alert_inbox.dart';
import 'package:alkong_yakong/features/profile/application/current_user_controller.dart';
import 'package:alkong_yakong/features/profile/data/user_repository.dart';
import 'package:alkong_yakong/features/profile/presentation/change_password_screen.dart';

class PasswordUsers extends UserRepository {
  int calls = 0;
  String? userId;
  String? current;
  String? next;
  bool fail = false;
  @override
  Future<void> changePassword(
    String id, {
    required String currentPassword,
    required String newPassword,
  }) async {
    calls++;
    userId = id;
    current = currentPassword;
    next = newPassword;
    if (fail) throw const ApiException('현재 비밀번호가 올바르지 않아요.');
  }
}

void main() {
  for (final name in ['김이박', ' 김이박 ', '김', 'Alice', '👩‍⚕️약사', '']) {
    testWidgets('avatar uses first visible character: $name', (tester) async {
      final expected = name.trim().isEmpty ? '님' : name.trim().characters.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              InitialAvatar(name: name),
              polar.InitialAvatar(name: name),
            ],
          ),
        ),
      );
      expect(find.text(expected), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
  for (final entry in {
    59: '느림',
    60: '정상',
    100: '정상',
    101: '빠름',
    114: '빠름',
  }.entries) {
    testWidgets(
      'patient card shows ${entry.key} bpm (${entry.value}) and centers dose notice',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              careOverviewProvider.overrideWith(
                (ref) async => CareOverview(
                  patients: [
                    CarePatient(
                      linkId: 'l',
                      patientId: 'p',
                      name: '사용자',
                      totalCount: 3,
                      doseStatus: 'overdue',
                      overdueDoseLabel: '아침 약',
                      heartRate: entry.key,
                    ),
                  ],
                ),
              ),
              guardianUnreadCountProvider.overrideWith((ref, id) async => 0),
            ],
            child: MaterialApp(
              theme: AppTheme.build(),
              home: Scaffold(body: CareFamilyScreen(onOpenPatient: (_) {})),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('최근 심박수 ${entry.key}bpm(${entry.value})'),
          findsOneWidget,
        );
        final heartText = find.text('최근 심박수 ${entry.key}bpm(${entry.value})');
        final text = tester.widget<Text>(heartText);
        expect(text.style!.fontSize, 15.5);
        expect(text.maxLines, 1);
        expect(text.softWrap, isFalse);
        final spans = (text.textSpan! as TextSpan).children!;
        expect((spans.first as TextSpan).style, isNull);
        expect(
          (spans.last as TextSpan).style!.color,
          entry.key < 60 || entry.key > 100 ? AppColors.danger : null,
        );
        final fit = find.ancestor(
          of: heartText,
          matching: find.byType(FittedBox),
        );
        expect(tester.widget<FittedBox>(fit).fit, BoxFit.scaleDown);
        expect(
          tester.getRect(heartText).right,
          lessThanOrEqualTo(tester.getRect(fit).right + 0.1),
        );
        expect(
          tester.widget<Text>(find.text('아침 약 복용 완료 기록이 없어요')).textAlign,
          TextAlign.center,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'password editor validates, masks fields and reports rejected password',
    (tester) async {
      MvpSession.userId = 'guardian-test';
      final users = PasswordUsers()..fail = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [userRepositoryProvider.overrideWithValue(users)],
          child: MaterialApp(
            theme: AppTheme.build(),
            home: const ChangePasswordScreen(),
          ),
        ),
      );
      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();
      expect(users.calls, 0);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'old123');
      await tester.enterText(fields.at(1), 'new456');
      await tester.enterText(fields.at(2), 'different');
      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();
      expect(users.calls, 0);
      await tester.enterText(fields.at(2), 'new456');
      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();
      expect(users.calls, 1);
      expect(users.userId, 'guardian-test');
      expect(users.current, 'old123');
      expect(users.next, 'new456');
      expect(find.text('현재 비밀번호가 올바르지 않아요.'), findsOneWidget);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.obscureText, isTrue);
      }
      users.fail = false;
      await tester.tap(find.text('저장하기'));
      await tester.pumpAndSettle();
      expect(find.text('비밀번호를 수정했어요'), findsOneWidget);
      expect(users.calls, 2);
    },
  );
}
