import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class DurAnalysisScreen extends StatelessWidget {
  const DurAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('복약 안전도'), backgroundColor: kPrimary),
      body: const Center(child: Text('DUR 위험도 분석 구현 예정')),
    );
  }
}
