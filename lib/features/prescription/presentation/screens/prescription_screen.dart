import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class PrescriptionScreen extends StatelessWidget {
  const PrescriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('처방전 등록'),
        backgroundColor: kPrimary,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(24), border: Border.all(color: kBorder, width: 2, strokeAlign: BorderSide.strokeAlignInside)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(color: kPrimaryLight, borderRadius: BorderRadius.circular(24)),
                      child: const Center(child: Text('📸', style: TextStyle(fontSize: 36))),
                    ),
                    const SizedBox(height: 16),
                    const Text('처방전 또는 약봉투를', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kText)),
                    const Text('촬영해주세요', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kText)),
                    const SizedBox(height: 8),
                    Text('OCR이 약 정보를 자동으로 추출해요', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kPrimaryLight, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('추출된 정보는 확인 후 등록돼요. 잘못된 부분은 수정할 수 있어요.', style: TextStyle(fontSize: 12, color: kPrimaryDark))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                child: const Text('📋  촬영하기', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
