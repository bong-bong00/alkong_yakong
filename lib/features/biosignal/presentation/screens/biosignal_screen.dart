import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class BiosignalScreen extends StatelessWidget {
  const BiosignalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('생체 신호'), backgroundColor: kPrimary,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // 센서 연결
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Column(children: [
              Container(width: 72, height: 72, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(22)),
                child: Icon(Icons.bluetooth_searching_rounded, color: Colors.grey[400], size: 36)),
              const SizedBox(height: 14),
              const Text('폴라 베리티 센스', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
              const SizedBox(height: 4),
              Text('연결 대기 중', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.bluetooth_rounded, color: kPrimary, size: 20),
                  label: const Text('센서 연결', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: kPrimary, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                )),
            ]),
          ),
          const SizedBox(height: 16),

          // 지표
          Row(children: [
            Expanded(child: _Metric(emoji: '❤️', label: '심박수', value: '--', unit: 'bpm')),
            const SizedBox(width: 10),
            Expanded(child: _Metric(emoji: '📊', label: 'RMSSD', value: '--', unit: 'ms')),
            const SizedBox(width: 10),
            Expanded(child: _Metric(emoji: '✅', label: '상태', value: '--', unit: '')),
          ]),
          const SizedBox(height: 16),

          // 측정 버튼
          SizedBox(width: double.infinity, height: 56,
            child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(backgroundColor: kPrimary, disabledBackgroundColor: Colors.grey[200],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              child: Text('⏱️  측정 시작 (5분)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey[400])),
            )),
          const SizedBox(height: 8),
          Text('센서를 연결한 후 측정을 시작해주세요', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          const SizedBox(height: 20),

          // 측정 기록
          Container(
            width: double.infinity, padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('최근 측정 기록', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
              const SizedBox(height: 16),
              Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text('📝', style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 8),
                  Text('측정 기록이 없습니다', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                ]),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String emoji; final String label; final String value; final String unit;
  const _Metric({required this.emoji, required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: kTextSub)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kText)),
        if (unit.isNotEmpty) Text(unit, style: const TextStyle(fontSize: 10, color: kTextSub)),
      ]),
    );
  }
}
