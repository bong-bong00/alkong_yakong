import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('복약 기록'), backgroundColor: kPrimary,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // 지표 카드
          Row(children: const [
            Expanded(child: _Stat(emoji: '✅', label: '오늘 완료', value: '2/3', color: kPrimary, bg: kPrimaryLight)),
            SizedBox(width: 10),
            Expanded(child: _Stat(emoji: '📈', label: '이번 주', value: '85%', color: kBlue, bg: kBlueLight)),
            SizedBox(width: 10),
            Expanded(child: _Stat(emoji: '📅', label: '처방 잔여', value: '12일', color: kOrange, bg: kOrangeLight)),
          ]),
          const SizedBox(height: 20),

          // 달력
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(icon: const Icon(Icons.chevron_left_rounded, color: kTextSub), onPressed: () {}),
                const Text('2026년 5월', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
                IconButton(icon: const Icon(Icons.chevron_right_rounded, color: kTextSub), onPressed: () {}),
              ]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['일','월','화','수','목','금','토'].map((d) => SizedBox(width: 36,
                  child: Center(child: Text(d, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: d == '일' ? kRed : kTextSub))))).toList()),
              Padding(padding: const EdgeInsets.all(28),
                child: Center(child: Text('달력 위젯 구현 예정', style: TextStyle(fontSize: 13, color: Colors.grey[400])))),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                _Dot(color: kGreenLight, border: kGreen, label: '완료'),
                SizedBox(width: 14),
                _Dot(color: kOrangeLight, border: kOrange, label: '누락'),
                SizedBox(width: 14),
                _Dot(color: kPinkLight, border: kPink, label: '미복약'),
              ]),
            ]),
          ),
          const SizedBox(height: 16),

          // 날짜 상세
          Container(
            width: double.infinity, padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kPrimary, width: 1.5)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('5월 12일 (월)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kText)),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: kPrimaryLight, borderRadius: BorderRadius.circular(12)),
                  child: const Text('완료', style: TextStyle(fontSize: 11, color: kPrimary, fontWeight: FontWeight.w700))),
              ]),
              const Divider(height: 20),
              const _Record(time: '아침 08:00', pills: '암로디핀 5mg, 아스피린 100mg', status: '✓ 복약 완료'),
              const Divider(height: 14),
              const _Record(time: '점심 12:30', pills: '메트포르민 500mg', status: '✓ 복약 완료'),
              const Divider(height: 14),
              const _Record(time: '저녁 18:00', pills: '메트포르민 500mg, 암로디핀 5mg', status: '✓ 복약 완료'),
              const Divider(height: 16),
              Row(children: [
                const Text('💓', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text('RMSSD 42→38ms | 심박수 평균 74bpm', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String emoji; final String label; final String value; final Color color; final Color bg;
  const _Stat({required this.emoji, required this.label, required this.value, required this.color, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: kTextSub)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
    ]),
  );
}

class _Dot extends StatelessWidget {
  final Color color; final Color border; final String label;
  const _Dot({required this.color, required this.border, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: border))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11, color: kTextSub)),
  ]);
}

class _Record extends StatelessWidget {
  final String time; final String pills; final String status;
  const _Record({required this.time, required this.pills, required this.status});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
    const SizedBox(height: 2),
    Text(pills, style: const TextStyle(fontSize: 12, color: kTextSub)),
    const SizedBox(height: 2),
    Text(status, style: const TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w600)),
  ]);
}
