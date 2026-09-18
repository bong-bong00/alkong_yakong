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
import 'current_user_controller.dart';

/// 로그인·가입이 끝난 사람으로 앱을 연다.
///
/// 앞사람이 보던 약·가족·기록이 남아 있으면 남의 정보가 보인다.
/// 사람이 바뀔 때마다 사람에게 딸린 값을 모두 버리고 다시 읽는다.
Future<void> startSession(WidgetRef ref, UserProfile user) async {
  MvpSession.userId = user.id;
  MvpSession.isPregnant = user.isPregnant;
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
}
