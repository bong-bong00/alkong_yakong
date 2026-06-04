import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class PrescriptionScreen extends StatelessWidget {
  const PrescriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('처방전 등록'), backgroundColor: kPrimary),
      body: const Center(child: Text('처방전 OCR 구현 예정')),
    );
  }
}
