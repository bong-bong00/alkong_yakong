import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers/user_role.dart';
import 'core/session/auth_session.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/signup_screen.dart';
import 'features/biosignal/presentation/screens/heartbeat_screen.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';
import 'features/dashboard/presentation/screens/guardian_home_screen.dart';
import 'features/dashboard/presentation/screens/home_screen.dart';
import 'features/drug_explain/drug_explain_screen.dart';
import 'features/dur_analysis/presentation/screens/dur_analysis_screen.dart';
import 'features/medication/application/medication_controller.dart';
import 'features/onboarding/presentation/screens/first_run_screen.dart';
import 'features/prescription/presentation/screens/prescription_screen.dart';
import 'features/reminder/presentation/screens/lock_screen_alert.dart';
import 'features/voice/presentation/screens/voice_screen.dart';

/// 화면을 둘러보는 동안 로그인을 건너뛴다.
///
/// **지금은 켜져 있다** — 앱을 실행하면 바로 오늘 홈으로 들어간다.
/// 화면 확인이 끝나면 defaultValue를 false로 바꿔 원래대로 되돌릴 것.
/// 되돌리기 전에도 `flutter run --dart-define=SKIP_LOGIN=false` 로
/// 로그인 화면을 그때그때 확인할 수 있다.
// TODO: 확인이 끝나면 defaultValue: false 로 되돌린다.
const bool kSkipLogin = bool.fromEnvironment('SKIP_LOGIN', defaultValue: true);

final _router = GoRouter(
  initialLocation: kSkipLogin ? '/' : '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
    GoRoute(path: '/', builder: (context, state) => const RoleShell()),
    GoRoute(
      path: '/guardian',
      builder: (context, state) => const GuardianHomeScreen(),
    ),
    GoRoute(
      path: '/first-run',
      builder: (context, state) => const FirstRunScreen(),
    ),
    GoRoute(
      path: '/prescription',
      builder: (context, state) => const PrescriptionScreen(),
    ),
    GoRoute(
      path: '/dur-analysis',
      builder: (context, state) => const DurAnalysisScreen(),
    ),
    GoRoute(
      path: '/biosignal',
      builder: (context, state) => const HeartbeatScreen(),
    ),
    GoRoute(path: '/voice', builder: (context, state) => const VoiceScreen()),
    GoRoute(
      path: '/alarm',
      builder: (context, state) => const LockScreenAlertRoute(),
    ),
    // 아직 리디자인이 닿지 않은 화면들.
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/drug-explain',
      builder: (context, state) => const DrugExplainScreen(),
    ),
  ],
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthSession.load();
  runApp(const ProviderScope(child: AlkongYakongApp()));
}

class AlkongYakongApp extends StatelessWidget {
  const AlkongYakongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '알콩약콩',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      // 앱 안에 글자 크기 설정을 두지 않고 시스템 설정을 그대로 따른다.
      // (MediaQuery.textScaler를 건드리지 않는 것이 곧 그 구현이다.)
      routerConfig: _router,
    );
  }
}

/// 역할에 따라 환자 쉘과 보호자 쉘을 갈아 끼운다.
/// 내 정보 탭의 "보호자 화면으로 바꾸기"가 이 provider를 바꾼다.
class RoleShell extends ConsumerWidget {
  const RoleShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(userRoleProvider);
    return switch (role) {
      UserRole.patient => const HomeScreen(),
      UserRole.guardian => const GuardianHomeScreen(),
    };
  }
}

/// 5b 잠금화면 알림을 앱 안에서 확인해 보기 위한 라우트.
/// 실제 알림은 플랫폼 알림으로 그린다 — [LockScreenAlert] 주석 참고.
class LockScreenAlertRoute extends ConsumerWidget {
  const LockScreenAlertRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(medicationProvider);
    final dose = today.nextDose ?? today.doses.last;

    return LockScreenAlert(
      dose: dose,
      now: DateTime.now(),
      onTake: () {
        ref.read(medicationProvider.notifier).take(dose.slot);
        context.pop();
      },
      onSnooze: () {
        ref.read(medicationProvider.notifier).snooze(dose.slot);
        context.pop();
      },
    );
  }
}
