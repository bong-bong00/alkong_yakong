import '../../../core/network/api_client.dart';

/// 가족에게 처방전을 부탁한 결과.
enum PrescriptionHelpOutcome {
  /// 보호자에게 알림을 남겼다.
  sent,

  /// 연결된 보호자가 없다. 부탁할 사람이 없는 것이다.
  noGuardian,

  /// 서버에 닿지 못했다.
  failed,
}

/// 부탁한 결과와, 누구에게 갔는지.
class PrescriptionHelpResult {
  final PrescriptionHelpOutcome outcome;

  /// 알림을 받은 가족 호칭들 ("딸 김지안").
  final List<String> guardians;

  const PrescriptionHelpResult(this.outcome, {this.guardians = const []});

  bool get isSent => outcome == PrescriptionHelpOutcome.sent;
}

/// "가족에게 부탁하기"를 서버에 알리는 길.
///
/// 부탁은 **보호자에게 알림으로 남는다**. 어르신 화면에서 깃발만 세우면
/// 가족은 부탁받은 줄도 모른 채 어르신만 기다리게 된다.
class PrescriptionHelpRepository {
  PrescriptionHelpRepository({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<PrescriptionHelpResult> ask(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) {
      return const PrescriptionHelpResult(PrescriptionHelpOutcome.failed);
    }
    try {
      final response = await _api.post(
        '/api/v1/users/${Uri.encodeComponent(id)}/prescription-help-requests',
        body: const {},
      );
      if (response is! Map) {
        return const PrescriptionHelpResult(PrescriptionHelpOutcome.failed);
      }
      if (response['sent'] != true) {
        return const PrescriptionHelpResult(PrescriptionHelpOutcome.noGuardian);
      }
      final raw = response['guardians'];
      return PrescriptionHelpResult(
        PrescriptionHelpOutcome.sent,
        guardians: [
          if (raw is List)
            for (final name in raw)
              if (name?.toString().trim().isNotEmpty ?? false)
                name.toString().trim(),
        ],
      );
    } catch (_) {
      // 못 보냈으면 못 보냈다고 한다. 보낸 척하면 어르신이 기다린다.
      return const PrescriptionHelpResult(PrescriptionHelpOutcome.failed);
    }
  }
}
