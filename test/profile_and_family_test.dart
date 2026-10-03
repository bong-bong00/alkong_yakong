import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/theme/app_theme.dart';
import 'package:alkong_yakong/core/widgets/senior_header.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/profile_edit_screen.dart';
import 'package:alkong_yakong/features/medicines/presentation/screens/my_medicines_screen.dart';
import 'package:alkong_yakong/features/prescription/presentation/screens/add_medicine_screen.dart';
import 'package:alkong_yakong/features/profile/application/current_user_controller.dart';
import 'package:alkong_yakong/features/profile/data/user_repository.dart';
import 'package:alkong_yakong/features/profile/domain/user_profile.dart';
import 'package:alkong_yakong/features/profile/presentation/screens/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = UserProfile(
  id: 'u1',
  role: 'patient',
  name: '김복자',
  bloodType: 'B형',
  allergies: ['페니실린'],
  diseases: ['고혈압'],
  pastHistory: true,
  familyHistory: false,
  pastIllnesses: ['뇌졸중'],
  familyIllnesses: [],
);

/// 서버를 타지 않고 정해 둔 사람을 돌려준다.
class _FixedUser extends CurrentUserController {
  @override
  Future<UserProfile?> build() async => _user;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(_FixedUser.new),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.build(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SizedBox.shrink(),
        ).copyWithChild(child),
      ),
    );
  }

  group('내 정보 수정', () {
    testWidgets('회원가입에서 물은 과거 병력과 가족력을 여기서도 고친다', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(const ProfileEditScreen()));
      await tester.pumpAndSettle();

      expect(find.text('예전에 크게 아팠던 적이 있나요?'), findsOneWidget);
      expect(find.text('부모님이나 형제가 앓은 병이 있나요?'), findsOneWidget);

      // 있다고 답해 둔 쪽은 적어 둔 병이 함께 보인다.
      expect(find.text('뇌졸중'), findsOneWidget);

      // 없다고 답해 둔 쪽을 있다로 바꾸면 그 자리에서 병을 넣을 수 있다.
      expect(find.text('더 넣기'), findsNWidgets(3));
      final familyYes = find.text('네, 있어요').last;
      await tester.ensureVisible(familyYes);
      await tester.pumpAndSettle();
      await tester.tap(familyYes);
      await tester.pumpAndSettle();
      expect(find.text('더 넣기'), findsNWidgets(4));
    });

    testWidgets('보호자에게는 건강 정보를 묻지 않는다', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(const ProfileEditScreen(isGuardian: true)));
      await tester.pumpAndSettle();

      expect(find.text('예전에 크게 아팠던 적이 있나요?'), findsNothing);
      expect(find.text('부모님이나 형제가 앓은 병이 있나요?'), findsNothing);
    });
  });

  group('처방전 넣기 · 가족에게 부탁하기', () {
    testWidgets('가족이 아직 안 넣었으면 그렇다고 말한다', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var asked = 0;
      var checked = 0;
      await tester.pumpWidget(
        wrap(
          AddMedicineScreen(
            onPick: (_) {},
            guardianTitle: '딸 지안 님',
            onAskFamily: () async {
              asked++;
              return true;
            },
            onCheckFamily: () async {
              checked++;
              return false;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('가족에게 부탁하기'));
      await tester.pumpAndSettle();

      // 부탁을 보내고 나서 바로 한 번 확인한다.
      expect(asked, 1);
      expect(checked, 1);
      expect(find.textContaining('아직 처방전을 넣지 않으셨어요'), findsOneWidget);
      expect(find.text('넣으셨는지 확인하기'), findsOneWidget);

      // 다시 눌러 확인할 수 있다. 기다리는 동안 할 수 있는 일이 있어야 한다.
      await tester.tap(find.text('넣으셨는지 확인하기'));
      await tester.pumpAndSettle();
      expect(checked, 2);
    });

    testWidgets('가족이 이미 넣었으면 아무 말도 붙이지 않는다', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          AddMedicineScreen(
            onPick: (_) {},
            guardianTitle: '딸 지안 님',
            onAskFamily: () async => true,
            // 부른 쪽이 다음 화면으로 넘긴다.
            onCheckFamily: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('가족에게 부탁하기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('아직 처방전을 넣지 않으셨어요'), findsNothing);
    });
  });

  testWidgets('받을 가족이 없으면 부탁했다고 말하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var checked = 0;
    await tester.pumpWidget(
      wrap(
        AddMedicineScreen(
          onPick: (_) {},
          guardianTitle: '딸 지안 님',
          // 연결된 가족이 없어 못 보낸 경우.
          onAskFamily: () async => false,
          onCheckFamily: () async {
            checked++;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('가족에게 부탁하기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('부탁했어요'), findsNothing);
    expect(checked, 0);
    // 다시 부탁해 볼 수 있게 단추는 그대로 있다.
    expect(find.text('가족에게 부탁하기'), findsOneWidget);
  });

  testWidgets('내 약 목록에는 뒤로 가는 머리띠가 없다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const MyMedicinesScreen()));
    await tester.pump();

    expect(find.byType(SeniorBackHeader), findsNothing);
    expect(find.text('내 약 목록'), findsNothing);
  });

  testWidgets('탈퇴를 마치면 탈퇴됐다고 말하고 로그인으로 돌아간다', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var deleted = 0;
    final repository = UserRepository(
      apiClient: ApiClient(
        client: MockClient((request) async {
          if (request.method == 'DELETE') deleted++;
          return http.Response(
            jsonEncode({'ok': true}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final router = GoRouter(
      initialLocation: '/account',
      routes: [
        GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('로그인 화면')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(_FixedUser.new),
          userRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          theme: AppTheme.build(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 카드 제목과 단추에 같은 말이 있다. 누르는 쪽은 단추다.
    await tester.tap(find.text('탈퇴').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('네, 탈퇴할게요'));
    await tester.pumpAndSettle();

    expect(deleted, 1);
    // 화면이 바뀌기 전에 끝났다고 말한다.
    expect(find.text('탈퇴되었습니다'), findsOneWidget);
    expect(find.text('로그인 화면'), findsNothing);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('로그인 화면'), findsOneWidget);
  });
}

extension on MediaQuery {
  Widget copyWithChild(Widget child) => MediaQuery(data: data, child: child);
}
