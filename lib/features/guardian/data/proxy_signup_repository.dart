import 'dart:math';

import '../../../core/network/api_client.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/proxy_signup.dart';

/// 가족이 대신 만들어 드리는 어르신 계정.
///
/// 두 가지를 한 흐름으로 묶는다.
/// ① 어르신 계정 만들기 — `POST /api/v1/users`
/// ② 지금 로그인한 자녀분을 보호자로 붙이기 — `POST /api/v1/guardians`
///
/// **확인번호는 아직 문자로 나가지 않는다.** 문자 발송 창구가 붙기 전까지는
/// 이 기기 안에서 만들고 이 기기 안에서 맞춰 본다. 그래서 번호를 화면에
/// 한 번 보여준다 — 안 보여주면 자녀분이 넣을 번호를 알 길이 없다.
/// 창구가 생기면 [sendCode]의 발송 한 줄만 서버 호출로 바꾸고
/// [showsCodeOnDevice]를 false로 내린다.
class ProxySignupRepository {
  ProxySignupRepository({ApiClient? apiClient, Random? random})
    : _api = apiClient ?? ApiClient(),
      _random = random ?? Random.secure();

  final ApiClient _api;
  final Random _random;

  /// 문자 창구가 붙기 전까지 확인번호를 기기에 그대로 보여준다.
  static const bool showsCodeOnDevice = true;

  /// 확인번호가 살아 있는 시간. 화면 안내("3분 안에 적어야 해요")와 같은 값이다.
  static const Duration codeLifetime = Duration(minutes: 3);

  /// 어르신 전화기로 확인번호를 보낸다.
  Future<ProxyVerification> sendCode(ProxyElderDraft draft) async {
    if (draft.phoneDigits.length < 10) {
      throw const ApiException('어르신 전화번호를 다시 확인해 주세요.');
    }
    final code = List.generate(6, (_) => _random.nextInt(10)).join();
    // TODO: 문자 발송 창구가 붙으면 여기서 서버에 보내기를 청한다.
    return ProxyVerification(
      code: code,
      expiresAt: DateTime.now().add(codeLifetime),
    );
  }

  /// 어르신 계정을 만들고, 자녀분을 보호자로 붙인다.
  ///
  /// 이 일은 언제나 로그인한 자녀분이 한다. 그 사람이 곧 보호자다 —
  /// 일반 회원가입 마지막 단계에서 보호자 연락처를 받아 등록하는 것과
  /// 같은 일을, 계정을 만드는 그 자리에서 한다.
  ///
  /// 계정은 만들어졌는데 연결만 실패할 수도 있다. 그때도 계정을 지우지 않고
  /// [ProxySignupResult.guardianLinked]를 false로 돌려준다 — 화면이
  /// "계정은 만들어졌고 연결만 다시 하면 된다"고 말할 수 있어야 한다.
  Future<ProxySignupResult> createAccount({
    required ProxyElderDraft draft,
    required ProxyVerification verification,
    required UserProfile guardian,
  }) async {
    final created = await _api.post(
      '/api/v1/users',
      body: {
        'name': draft.name,
        'role': 'patient',
        'phone': draft.phone,
        // 확인번호를 그대로 첫 비밀번호로 둔다. 어르신이 나중에 바꿀 수 있다.
        'password': verification.code,
      },
      timeout: const Duration(seconds: 15),
    );
    if (created is! Map) {
      throw const ApiException('어르신 계정을 만들지 못했어요.');
    }
    final patientId = created['id']?.toString().trim() ?? '';
    if (patientId.isEmpty) {
      throw const ApiException('어르신 계정을 만들지 못했어요.');
    }

    var linked = false;
    try {
      await _api.post(
        '/api/v1/guardians',
        body: {
          'user_id': patientId,
          'guardian_name': guardian.name,
          // 어르신이 자녀분을 부르는 말.
          'relationship': childRelationOf(guardian),
          'phone': guardian.phone,
          // 자녀분이 어르신을 부르는 말 ("어머니").
          'patient_relation': draft.relation,
        },
      );
      linked = true;
    } catch (_) {
      linked = false;
    }

    return ProxySignupResult(
      patientId: patientId,
      name: draft.name,
      phone: draft.phone,
      relation: draft.relation,
      initialPassword: verification.code,
      guardianLinked: linked,
      guardianName: guardian.name,
    );
  }

  /// 어르신이 자녀분을 부르는 말. 자녀분 성별에서 고른다.
  /// 모르면 "자녀" — 틀린 호칭을 지어내지 않는다.
  static String childRelationOf(UserProfile guardian) {
    return switch (guardian.gender?.toUpperCase()) {
      'F' => '딸',
      'M' => '아들',
      _ => '자녀',
    };
  }
}
