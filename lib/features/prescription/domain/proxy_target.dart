/// 보호자가 어르신 **대신** 처방전을 넣을 때, 그 약이 누구에게 들어가는지.
/// 위치: lib/features/prescription/domain/proxy_target.dart
library;

class ProxyTarget {
  /// 약이 들어갈 어르신 계정 id. 보호자 자신의 id가 아니다.
  final String patientId;

  /// 화면마다 계속 달고 다니는 이름 — "어머니 · 김복자".
  ///
  /// 여러 어르신을 함께 보는 보호자가 엉뚱한 분에게 약을 넣는 일이 가장
  /// 무섭다. 그래서 고른 뒤에도 찍기·확인 화면 위에 이름을 계속 적어 둔다.
  final String title;

  const ProxyTarget({required this.patientId, required this.title});
}
