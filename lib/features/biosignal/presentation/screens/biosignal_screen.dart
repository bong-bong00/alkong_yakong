import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class BiosignalScreen extends StatelessWidget {
  const BiosignalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('생체 신호'), backgroundColor: kPrimary),
      body: const Center(child: Text('폴라 센서 연동 구현 예정')),
    );
  }
}
