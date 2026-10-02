import 'dart:async';

import 'dev_mock.dart';
import 'features/guardian/presentation/screens/guardian_prescription_screen.dart';
import 'features/prescription/presentation/screens/medicine_arrived_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers/user_role.dart';
import 'core/session/auth_session.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/signup_screen.dart';
import 'features/biosignal/presentation/screens/heart_screen.dart';
import 'features/biosignal/presentation/screens/measure_screen.dart';
import 'features/biosignal/presentation/screens/saved_screen.dart';
import 'features/biosignal/domain/heart_data.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';
import 'features/dashboard/presentation/screens/guardian_home_screen.dart';
import 'features/dashboard/presentation/screens/home_screen.dart';
import 'features/drug_explain/drug_explain_screen.dart';
import 'features/medication/application/medication_controller.dart';
import 'features/medicines/presentation/screens/drug_detail_screen.dart';
import 'features/onboarding/presentation/screens/first_run_screen.dart';
import 'features/prescription/presentation/screens/manual_medicine_screen.dart';
import 'features/prescription/presentation/screens/prescription_screen.dart';
import 'features/prescription/presentation/screens/schedule_days_screen.dart';
import 'features/profile/application/session_actions.dart';
import 'features/profile/data/user_repository.dart';
import 'features/reminder/application/alarm_preferences.dart';
import 'features/reminder/application/reminder_notifications.dart';
import 'features/reminder/presentation/screens/lock_screen_alert.dart';

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final publicRoute =
        state.matchedLocation == '/login' || state.matchedLocation == '/signup';
    if (!AuthSession.isLoggedIn) return publicRoute ? null : '/login';
    return publicRoute ? '/' : null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
    GoRoute(path: '/', builder: (context, state) => const RoleShell()),
    GoRoute(
      path: '/guardian',
      builder: (context, state) =>
          GuardianHomeScreen(alertsRepository: mockAlertRepository()),
    ),
    GoRoute(
      path: '/first-run',
      builder: (context, state) => const FirstRunScreen(),
    ),
    GoRoute(
      path: '/guardian-prescription',
      builder: (context, state) => const GuardianPickPatientScreen(),
    ),
    GoRoute(
      path: '/medicine-arrived',
      builder: (context, state) {
        final extra = state.extra;
        final data = extra is Map ? Map<String, dynamic>.from(extra) : const {};
        final raw = data['medicines'];
        return MedicineArrivedScreen(
          senderTitle: data['sender']?.toString() ?? '가족',
          medicines: [
            if (raw is List)
              for (final item in raw)
                if (item is Map)
                  {
                    for (final entry in item.entries)
                      entry.key.toString(): entry.value?.toString() ?? '',
                  },
          ],
        );
      },
    ),
    // 화면 확인용 임시 경로. 확인이 끝나면 지운다.
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
      // 내 약은 아래 탭에 있는 자리다. 따로 쌓지 않고 그 탭을 연다.
      builder: (context, state) =>
          const HomeScreen(initialTab: HomeTab.medicines),
    ),
    GoRoute(
      path: '/medicines/:code',
      builder: (context, state) =>
          DrugDetailScreen(medicineCode: state.pathParameters['code'] ?? ''),
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
      builder: (context, state) => HeartScreen(
        routeBasedMeasurement: true,
        repository: mockHeartRepository(),
      ),
      routes: [
        GoRoute(
          path: 'measure',
          builder: (context, state) {
            final args = state.extra;
            return MeasureScreen(
              guardianTitle: args is HeartMeasureRouteArgs
                  ? args.guardianTitle
                  : '',
              sensor: args is HeartMeasureRouteArgs ? args.sensor : null,
              measurementContext: args is HeartMeasureRouteArgs
                  ? args.measurementContext
                  : HeartMeasurementContext.general,
              onSaved: args is HeartMeasureRouteArgs ? args.onSaved : null,
              returnToPreviousScreen: true,
            );
          },
        ),
        GoRoute(
          path: 'saved',
          builder: (context, state) {
            final args = state.extra! as HeartSavedRouteArgs;
            return SavedScreen(
              bpm: args.bpm,
              savedAt: args.savedAt,
              measurementContext: args.measurementContext,
              guardianTitle: args.guardianTitle,
              onConfirmed: args.onSaved,
              returnToPreviousScreen: true,
            );
          },
        ),
      ],
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
      // 약 자세히에서 "이 약 물어보기"로 오면 그 약을 고른 채로 연다.
      builder: (context, state) => DrugExplainScreen(
        initialMedicine: state.extra as String?,
        // 가짜 데이터를 켠 개발 빌드에서는 이 화면도 서버를 타지 않는다.
        apiClient: mockData ? mockPharmacistApi() : null,
        medicationApiClient: mockData ? mockPharmacistApi() : null,
      ),
    ),
  ],
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 어르신이 폰을 눕혀 쥐어도 화면이 돌지 않는다.
  unawaited(
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  );
  // 가짜 데이터는 개발 빌드에서만 깔린다. 배포 빌드에서는 빈 목록이다.
  final container = ProviderContainer(overrides: devMockOverrides());
  final sessionReady = _restoreSession(container);
  // 가짜 이전 대화는 로그인한 사람이 정해진 뒤에 적는다.
  unawaited(sessionReady.then((_) => seedMockConversations()));
  // 알림 초기화는 화면·로그인 확인을 기다리게 하지 않는다.
  final remindersReady = ReminderNotifications.instance.initialize().catchError(
    (_) {},
  );
  unawaited(
    _warmAlarmPreferences(container, sessionReady, remindersReady).catchError(
      (Object error) => debugPrint(
        '[STARTUP_DIAG] alarm_prepare_failed=${error.runtimeType}',
      ),
    ),
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: _StartupGate(sessionReady: sessionReady),
    ),
  );
}

Future<void> _restoreSession(ProviderContainer container) async {
  final timer = Stopwatch()..start();
  final restoredUser = await restorePersistedSession(UserRepository());
  if (restoredUser != null) {
    container.read(userRoleProvider.notifier).state = restoredUser.isGuardian
        ? UserRole.guardian
        : UserRole.patient;
  }
  // No login is required for the demonstration medicine. Session restoration
  // clears the ID when signed out, so initialize the shared demo user here.
  if (restoredUser == null || !restoredUser.isGuardian) {
    await AuthSession.ensurePresentationMedicine();
  }
  debugPrint('[STARTUP_DIAG] session_restore_ms=${timer.elapsedMilliseconds}');
}

Future<void> _warmAlarmPreferences(
  ProviderContainer container,
  Future<void> sessionReady,
  Future<void> remindersReady,
) async {
  await Future.wait([sessionReady, remindersReady]);
  // 사용자 확인과 플러그인 준비가 끝난 뒤에만 알림을 예약한다.
  container.read(alarmPreferencesProvider);
}

class _StartupGate extends StatelessWidget {
  final Future<void> sessionReady;

  const _StartupGate({required this.sessionReady});

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: sessionReady,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done) {
        return const AlkongYakongApp();
      }
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    },
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
      UserRole.guardian => GuardianHomeScreen(
        alertsRepository: mockAlertRepository(),
      ),
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
