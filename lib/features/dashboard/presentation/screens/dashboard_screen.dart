import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('복약 기록'), backgroundColor: kPrimary),
      body: const Center(child: Text('대시보드 구현 예정')),
    );
  }
}
