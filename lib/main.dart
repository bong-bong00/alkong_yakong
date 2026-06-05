import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/constants/app_colors.dart';
import 'features/dashboard/presentation/screens/home_screen.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';
import 'features/prescription/presentation/screens/prescription_screen.dart';
import 'features/dur_analysis/presentation/screens/dur_analysis_screen.dart';
import 'features/biosignal/presentation/screens/biosignal_screen.dart';
import 'features/drug_explain/drug_explain_screen.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
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
      builder: (context, state) => const BiosignalScreen(),
    ),
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

void main() {
  runApp(const ProviderScope(child: AlkongYakongApp()));
}

class AlkongYakongApp extends StatelessWidget {
  const AlkongYakongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '알콩약콩',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: kPrimary,
        scaffoldBackgroundColor: kBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimary,
          surface: kBackground,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      routerConfig: _router,
    );
  }
}
