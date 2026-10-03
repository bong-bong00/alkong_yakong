import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mode/app_mode.dart';
import '../../../core/providers/user_role.dart';
import '../../../core/session/auth_session.dart';
import '../../../core/session/mvp_session.dart';
import '../../dashboard/application/medication_history_provider.dart';
import '../../guardian/application/guardians_provider.dart';
import '../../medication/application/medication_controller.dart';
import '../../medicines/application/user_medicines_controller.dart';
import '../domain/user_profile.dart';
import '../data/user_repository.dart';
import 'current_user_controller.dart';

/// Restore only after the backend confirms both the saved UUID and role.
/// A cached preference alone cannot unlock protected screens.
Future<UserProfile?> restorePersistedSession(UserRepository repository) async {
  final timer = Stopwatch()..start();
  try {
    await AuthSession.load();
    debugPrint('[STARTUP_DIAG] saved_session_ms=${timer.elapsedMilliseconds}');
    timer.reset();
    final savedId = MvpSession.userId.trim();
    final canRestore =
        AuthSession.isLoggedIn && savedId.isNotEmpty && savedId != 'mvp-user';
    AuthSession.isLoggedIn = false;
    AuthSession.role = 'patient';
    MvpSession.userId = '';
    MvpSession.isPregnant = null;
    if (!canRestore) return null;

    final user = await repository.fetch(savedId);
    debugPrint(
      '[STARTUP_DIAG] team_user_fetch_ms=${timer.elapsedMilliseconds}',
    );
    if (user.id != savedId) return null;
    // 서버는 모르는 아이디로 물어 오면 "사용자"라는 빈 줄을 급히 만들어
    // 둔다(전화번호도 비밀번호도 없다). 그 껍데기로 들어가면 이름도
    // 건강 정보도 비어 있는 채로 로그인한 것처럼 보인다. 내 계정이
    // 아니므로 들이지 않고 로그인 화면으로 보낸다.
    if ((user.phone ?? '').trim().isEmpty) {
      debugPrint('[STARTUP_DIAG] placeholder_account_rejected');
      await AuthSession.logout();
      return null;
    }
    MvpSession.userId = user.id;
    MvpSession.isPregnant = user.isPregnant;
    await AuthSession.setLoggedIn(user.isGuardian ? 'guardian' : 'patient');
    return user;
  } catch (error) {
    debugPrint(
      '[STARTUP_DIAG] session_restore_failed_ms=${timer.elapsedMilliseconds} '
      'error_type=${error.runtimeType}',
    );
    AuthSession.isLoggedIn = false;
    AuthSession.role = 'patient';
    MvpSession.userId = '';
    MvpSession.isPregnant = null;
    return null;
  }
}

/// 로그인·가입이 끝난 사람으로 앱을 연다.
///
/// 앞사람이 보던 약·가족·기록이 남아 있으면 남의 정보가 보인다.
/// 사람이 바뀔 때마다 사람에게 딸린 값을 모두 버리고 다시 읽는다.
Future<void> startSession(WidgetRef ref, UserProfile user) async {
  final id = user.id.trim();
  final role = user.role.trim().toLowerCase();
  if (id.isEmpty ||
      id == 'mvp-user' ||
      (role != 'patient' && role != 'guardian')) {
    throw StateError('서버 사용자 정보를 확인할 수 없습니다.');
  }
  MvpSession.userId = id;
  MvpSession.isPregnant = user.isPregnant;
  await AuthSession.allowDevAutoLogin();
  await AuthSession.setLoggedIn(user.isGuardian ? 'guardian' : 'patient');
  ref.read(userRoleProvider.notifier).state = user.isGuardian
      ? UserRole.guardian
      : UserRole.patient;
  resetUserScopedData(ref);
}

/// 사람에게 딸린 화면 값을 모두 버린다.
///
/// 가입처럼 로그인 절차를 거치지 않고 사용자가 바뀌는 길에서도
/// 앞사람의 약·가족·기록이 화면에 남지 않게 한다.
void resetUserScopedData(WidgetRef ref) {
  ref
    ..invalidate(currentUserProvider)
    ..invalidate(guardiansProvider)
    ..invalidate(careOverviewProvider)
    ..invalidate(medicationProvider)
    ..invalidate(userMedicinesProvider)
    ..invalidate(medicationHistoryProvider);
}

/// 이 전화기에서 나간다.
///
/// 일반 모드로 되돌린다. 다음 사람이 쉬운 모드에 갇힌 채로
/// 로그인 화면을 만나지 않도록.
Future<void> endSession(WidgetRef ref) async {
  await ref.read(appModeProvider.notifier).set(AppMode.normal);
  await AuthSession.logout();
  MvpSession.medicineCode = '';
  MvpSession.latestOcrItems = <Map<String, dynamic>>[];
  MvpSession.latestOcrRegisteredAt = null;
  MvpSession.latestPrescriptionId = null;
  MvpSession.latestScheduleDates = <String>{};
  resetUserScopedData(ref);
}
