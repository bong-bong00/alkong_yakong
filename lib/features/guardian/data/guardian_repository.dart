import '../../../core/network/api_client.dart';
import '../../../core/session/mvp_session.dart';
import '../../dashboard/presentation/screens/patient_data.dart';

/// 초대를 보낸 결과.
///
/// 보냈는지 못 보냈는지를 분명히 나눈다. 실패했는데 목록에 올려 두면
/// 어르신은 초대를 받은 적이 없는데 보호자는 기다리게 된다.
class InviteResult {
  final PendingInvite? invite;
  final String? error;

  const InviteResult.sent(PendingInvite this.invite) : error = null;
  const InviteResult.failed(String this.error) : invite = null;

  bool get isSent => invite != null;
}

/// 돌보는 분 초대·목록.
class GuardianRepository {
  GuardianRepository({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// 어르신에게 초대를 보낸다.
  ///
  /// 서버가 받아 준 뒤에만 "보냈어요"라고 말한다.
  Future<InviteResult> invite({
    required String name,
    required String relation,
    required String phone,
    String? userId,
  }) async {
    final id = (userId ?? MvpSession.userId).trim();
    if (id.isEmpty) {
      return const InviteResult.failed('로그인이 필요해요');
    }
    try {
      await _apiClient.post(
        '/api/v1/guardians',
        body: {
          'user_id': id,
          'guardian_name': name,
          'relationship': relation,
          'phone': phone,
        },
      );
      return InviteResult.sent(
        PendingInvite(name: name, relation: relation, phone: phone),
      );
    } on ApiException catch (error) {
      return InviteResult.failed(error.message);
    } catch (_) {
      return const InviteResult.failed('초대를 보내지 못했어요. 잠시 후 다시 해주세요.');
    }
  }
}
