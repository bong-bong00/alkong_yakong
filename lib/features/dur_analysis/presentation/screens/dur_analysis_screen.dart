import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class DurAnalysisScreen extends StatelessWidget {
  const DurAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('복약 안전도'), backgroundColor: kPrimary,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Column(children: [
              Container(width: 72, height: 72, decoration: BoxDecoration(color: kGreenLight, borderRadius: BorderRadius.circular(22)),
                child: const Center(child: Text('🛡️', style: TextStyle(fontSize: 32)))),
              const SizedBox(height: 14),
              Text('현재 복약 안전도', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
              const SizedBox(height: 4),
              const Text('LOW', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: kGreen)),
              const SizedBox(height: 4),
              Text('위험 요소가 감지되지 않았습니다', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('위험도 기준', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
              const SizedBox(height: 14),
              _Level(emoji: '🔴', label: 'HIGH', desc: '병용 금기 약물 조합 감지', color: kRed),
              const Divider(height: 20),
              _Level(emoji: '🟡', label: 'MEDIUM', desc: '중복 성분 주의 필요', color: kOrange),
              const Divider(height: 20),
              _Level(emoji: '🟢', label: 'LOW', desc: '위험 요소 없음', color: kGreen),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('현재 복용약', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
              SizedBox(height: 14),
              _Drug(name: '암로디핀 5mg', desc: '고혈압 치료'),
              Divider(height: 16),
              _Drug(name: '메트포르민 500mg', desc: '당뇨 치료'),
              Divider(height: 16),
              _Drug(name: '아스피린 100mg', desc: '혈전 예방'),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Level extends StatelessWidget {
  final String emoji; final String label; final String desc; final Color color;
  const _Level({required this.emoji, required this.label, required this.desc, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(emoji, style: const TextStyle(fontSize: 16)),
    const SizedBox(width: 8),
    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))),
    const SizedBox(width: 10),
    Text(desc, style: const TextStyle(fontSize: 13, color: kText)),
  ]);
}

class _Drug extends StatelessWidget {
  final String name; final String desc;
  const _Drug({required this.name, required this.desc});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 36, height: 36, decoration: BoxDecoration(color: kPrimaryLight, borderRadius: BorderRadius.circular(12)),
      child: const Center(child: Text('💊', style: TextStyle(fontSize: 16)))),
    const SizedBox(width: 12),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
      Text(desc, style: const TextStyle(fontSize: 12, color: kTextSub)),
    ]),
  ]);
}
