import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers/user_role.dart';
import 'core/session/auth_session.dart';
import 'core/session/mvp_session.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/signup_screen.dart';
import 'features/biosignal/presentation/screens/heart_screen.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';
import 'features/dashboard/presentation/screens/guardian_home_screen.dart';
import 'features/dashboard/presentation/screens/home_screen.dart';
import 'features/drug_explain/drug_explain_screen.dart';
import 'features/dur_analysis/presentation/screens/dur_analysis_screen.dart';
import 'features/medication/application/medication_controller.dart';
import 'features/medicines/presentation/screens/drug_detail_screen.dart';
import 'features/medicines/presentation/screens/my_medicines_screen.dart';
import 'features/onboarding/presentation/screens/first_run_screen.dart';
import 'features/prescription/presentation/screens/manual_medicine_screen.dart';
import 'features/prescription/presentation/screens/prescription_screen.dart';
import 'features/prescription/presentation/screens/schedule_days_screen.dart';
import 'features/reminder/application/alarm_preferences.dart';
import 'features/reminder/application/reminder_notifications.dart';
import 'features/reminder/presentation/screens/lock_screen_alert.dart';

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final publicRoute = state.matchedLocation == '/login' ||
        state.matchedLocation == '/signup';
    if (!AuthSession.isLoggedIn) return publicRoute ? null : '/login';
    return publicRoute ? '/' : null;
  },
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
      path: '/manual-medicine',
      builder: (context, state) => const ManualMedicineScreen(),
    ),
    GoRoute(
      path: '/my-medicines',
      builder: (context, state) => const MyMedicinesScreen(),
    ),
    GoRoute(
      path: '/medicines/:code',
      builder: (context, state) =>
          DrugDetailScreen(medicineCode: state.pathParameters['code'] ?? ''),
    ),
    GoRoute(
      path: '/dur-analysis',
      builder: (context, state) {
        final extra = state.extra;
        return DurAnalysisScreen(
          initialResult: extra is Map ? Map<String, dynamic>.from(extra) : null,
        );
      },
    ),
    GoRoute(
      path: '/schedule-days',
      builder: (context, state) {
        final extra = state.extra;
        final id = extra is String
            ? extra
            : extra is Map
            ? extra['prescription_id']?.toString()
            : null;
        return ScheduleDaysScreen(prescriptionId: id);
      },
    ),
    GoRoute(
      path: '/biosignal',
      builder: (context, state) => const HeartScreen(),
    ),
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
  // A previous device user's persisted identity must not unlock this launch.
  // Only a successful login or signup starts the current session.
  AuthSession.isLoggedIn = false;
  MvpSession.userId = '';
  try {
    await ReminderNotifications.instance.initialize();
  } catch (_) {
    // 알림을 못 켜도 앱은 떠야 한다.
  }
  final container = ProviderContainer();
  // 알림 설정을 미리 읽어 두어야 내 정보 화면을 열지 않아도 약 시간 알림이 예약된다.
  container.read(alarmPreferencesProvider);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AlkongYakongApp(),
    ),
  );
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
    if (today.doses.isEmpty) {
      return const Scaffold(body: Center(child: Text('등록된 약이 없어요')));
    }
    final dose = today.nextDose ?? today.doses.last;

    return LockScreenAlert(
      dose: dose,
      now: DateTime.now(),
      onTake: () async {
        await ref.read(medicationProvider.notifier).take(dose.slot);
        if (context.mounted) context.pop();
      },
      onSnooze: () {
        ref.read(medicationProvider.notifier).snooze(dose.slot);
        context.pop();
      },
    );
  }
}
