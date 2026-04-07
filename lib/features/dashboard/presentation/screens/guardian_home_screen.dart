import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════
//  [보호자홈] 실시간 복약 모니터링 화면
// ════════════════════════════════════════════════════
class GuardianHomeScreen extends StatelessWidget {
  const GuardianHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '보호자 화면\n(개발 예정)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500),
      ),
    );
  }
}