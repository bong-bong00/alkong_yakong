/// 가족이 대신 만들어 드리는 어르신 계정 — 화면과 서버 사이에 오가는 값.
/// 위치: lib/features/guardian/domain/proxy_signup.dart
library;

/// 1/3 화면에서 자녀분이 적은 어르신 정보.
class ProxyElderDraft {
  /// 어르신 성함.
  final String name;

  /// 어르신 전화번호. 확인번호가 이 번호로 간다.
  final String phone;

  /// **자녀분이 부르는 호칭** ("어머니"). 어르신이 자녀를 부르는 말이 아니다.
  final String relation;

  const ProxyElderDraft({
    required this.name,
    required this.phone,
    required this.relation,
  });

  /// 하이픈을 뺀 번호. 같은 번호인지 견주는 자리에서 쓴다.
  String get phoneDigits => phone.replaceAll(RegExp(r'[^0-9]'), '');
}

/// 어르신 전화기로 보낸 확인번호 한 건.
///
/// 번호 자체를 들고 다니는 까닭은 아직 문자 창구가 없어서다 —
/// [ProxySignupRepository] 주석 참고.
class ProxyVerification {
  final String code;
  final DateTime expiresAt;

  const ProxyVerification({required this.code, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// 남은 시간. 다 지났으면 0초.
  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool matches(String input) =>
      !isExpired && input.replaceAll(RegExp(r'[^0-9]'), '') == code;
}

/// 계정을 다 만든 뒤 3/3 화면이 받는 것.
class ProxySignupResult {
  /// 새로 만들어진 어르신 계정 id.
  final String patientId;
  final String name;

  /// 어르신이 로그인할 때 쓰는 번호. 3/3 화면이 그대로 적어 준다.
  final String phone;

  /// 자녀분이 부르는 호칭 ("어머니").
  final String relation;

  /// 어르신이 처음 쓰는 비밀번호. 확인번호를 그대로 둔다.
  final String initialPassword;

  /// 보호자로 함께 등록됐는지. 계정은 만들어졌는데 연결만 실패할 수 있다.
  final bool guardianLinked;

  /// 보호자로 붙은 사람 이름 — 3/3 화면이 그대로 부른다.
  final String guardianName;

  const ProxySignupResult({
    required this.patientId,
    required this.name,
    required this.phone,
    required this.relation,
    required this.initialPassword,
    required this.guardianLinked,
    this.guardianName = '',
  });

  /// "어머니 · 김복자". 호칭을 모르면 이름만.
  String get title => relation.isEmpty ? name : '$relation · $name';
}
