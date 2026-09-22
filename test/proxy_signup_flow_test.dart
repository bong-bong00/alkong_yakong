import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_data.dart';
import 'package:alkong_yakong/features/guardian/application/guardians_provider.dart';
import 'package:alkong_yakong/features/guardian/data/proxy_signup_repository.dart';
import 'package:alkong_yakong/features/guardian/domain/proxy_signup.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/proxy_signup_screen.dart';
import 'package:alkong_yakong/features/profile/application/current_user_controller.dart';
import 'package:alkong_yakong/features/profile/domain/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버에 가지 않고 정해 둔 번호와 결과를 돌려준다.
class _FakeProxySignupRepository extends ProxySignupRepository {
  static const code = '482610';

  UserProfile? seenGuardian;
  ProxyElderDraft? seenDraft;

  @override
  Future<ProxyVerification> sendCode(ProxyElderDraft draft) async {
    seenDraft = draft;
    return ProxyVerification(
      code: code,
      expiresAt: DateTime.now().add(const Duration(minutes: 3)),
    );
  }

  @override
  Future<ProxySignupResult> createAccount({
    required ProxyElderDraft draft,
    required ProxyVerification verification,
    UserProfile? guardian,
  }) async {
    seenGuardian = guardian;
    return ProxySignupResult(
      patientId: 'made-up-patient',
      name: draft.name,
      phone: draft.phone,
      relation: draft.relation,
      initialPassword: verification.code,
      guardianLinked: true,
    );
  }
}

/// 로그인 화면에서 바로 들어온 경우 — 붙일 보호자가 없다.
class _LoggedOutCurrentUser extends CurrentUserController {
  @override
  Future<UserProfile?> build() async => null;
}

class _FakeCurrentUser extends CurrentUserController {
  @override
  Future<UserProfile?> build() async => const UserProfile(
    id: 'guardian-1',
    name: '김지안',
    role: 'guardian',
    phone: '010-1234-5678',
    gender: 'F',
  );
}

void main() {
  late _FakeProxySignupRepository repository;

  Widget wrap(Widget child, {bool loggedIn = true}) {
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          loggedIn ? _FakeCurrentUser.new : _LoggedOutCurrentUser.new,
        ),
        careOverviewProvider.overrideWith((ref) async => const CareOverview()),
      ],
      child: MaterialApp(home: child),
    );
  }

  setUp(() => repository = _FakeProxySignupRepository());

  testWidgets('자녀분이 어르신 정보를 적고 확인번호로 계정을 만든다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(ProxySignupScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('가족이 대신 회원가입 · 1 / 3'), findsOneWidget);
    expect(find.text('어르신 정보 적기'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '김복자');
    await tester.enterText(find.byType(TextField).at(1), '01023456789');
    await tester.tap(find.text('어머니'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('어르신 전화기로 확인번호 보내기'));
    await tester.tap(find.text('어르신 전화기로 확인번호 보내기'));
    await tester.pumpAndSettle();

    // 어르신 정보가 그대로 넘어갔는지.
    expect(repository.seenDraft?.name, '김복자');
    expect(repository.seenDraft?.relation, '어머니');
    expect(repository.seenDraft?.phoneDigits, '01023456789');

    expect(find.text('가족이 대신 회원가입 · 2 / 3'), findsOneWidget);
    expect(find.text('확인번호 넣기'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      _FakeProxySignupRepository.code,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('확인하고 계정 만들기'));
    await tester.tap(find.text('확인하고 계정 만들기'));
    await tester.pumpAndSettle();

    expect(find.text('가족이 대신 회원가입 · 3 / 3'), findsOneWidget);
    expect(find.text('어머니 계정이\n만들어졌어요'), findsOneWidget);
    expect(
      find.textContaining('자동으로 김지안 님이 보호자로 등록되었습니다'),
      findsOneWidget,
    );
    expect(find.text('처방전 대신 찍어드리기'), findsOneWidget);
    // 지금 로그인한 자녀분이 보호자로 넘어갔는지.
    expect(repository.seenGuardian?.name, '김지안');
  });

  testWidgets('내 정보를 못 읽으면 어르신 계정을 만들지 않는다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(ProxySignupScreen(repository: repository), loggedIn: false),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '김복자');
    await tester.enterText(find.byType(TextField).at(1), '01023456789');
    await tester.tap(find.text('어머니'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('어르신 전화기로 확인번호 보내기'));
    await tester.tap(find.text('어르신 전화기로 확인번호 보내기'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      _FakeProxySignupRepository.code,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('확인하고 계정 만들기'));
    await tester.tap(find.text('확인하고 계정 만들기'));
    await tester.pumpAndSettle();

    // 붙일 보호자를 모른 채로 어르신 계정만 덩그러니 만들지 않는다.
    expect(repository.seenGuardian, isNull);
    expect(find.text('확인번호 넣기'), findsOneWidget);
    expect(find.text('내 정보를 아직 못 읽었어요. 잠시 후 다시 해주세요'), findsOneWidget);
  });

  testWidgets('확인번호가 틀리면 계정을 만들지 않는다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(ProxySignupScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '김복자');
    await tester.enterText(find.byType(TextField).at(1), '01023456789');
    await tester.tap(find.text('어머니'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('어르신 전화기로 확인번호 보내기'));
    await tester.tap(find.text('어르신 전화기로 확인번호 보내기'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '000000');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('확인하고 계정 만들기'));
    await tester.tap(find.text('확인하고 계정 만들기'));
    await tester.pumpAndSettle();

    expect(repository.seenGuardian, isNull);
    expect(find.text('확인번호 넣기'), findsOneWidget);
    expect(find.text('확인번호가 맞지 않아요. 다시 확인해 주세요'), findsOneWidget);
  });

  testWidgets('성함·번호·관계를 다 채우기 전에는 확인번호를 보내지 않는다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(ProxySignupScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '김복자');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('어르신 전화기로 확인번호 보내기'));
    await tester.tap(find.text('어르신 전화기로 확인번호 보내기'));
    await tester.pumpAndSettle();

    expect(repository.seenDraft, isNull);
    expect(find.text('어르신 정보 적기'), findsOneWidget);
    expect(find.text('어르신 전화번호를 적어주세요'), findsOneWidget);
  });
}
