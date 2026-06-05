import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class GuardianHomeScreen extends StatefulWidget {
  const GuardianHomeScreen({super.key});
  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('보호자 모드 👀', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 2),
          Text('가족의 복약 상태를 확인하세요', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          const SizedBox(height: 20),

          // [환자 선택]
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _PatientChip(name: '김영수', emoji: '👴', isSelected: _selected == 0, onTap: () => setState(() => _selected = 0)),
                const SizedBox(width: 10),
                _PatientChip(name: '박순이', emoji: '👵', isSelected: _selected == 1, onTap: () => setState(() => _selected = 1)),
                const SizedBox(width: 10),
                _AddChip(),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // [오늘 복용약]
          _PillList(title: '오늘 복용약', badge: '2/3 완료', badgeColor: kPrimary, items: const [
            _PillItem(name: '암로디핀 5mg · 아침', status: 1),
            _PillItem(name: '메트포르민 500mg · 점심', status: 1),
            _PillItem(name: '메트포르민 500mg · 저녁', status: -1),
          ]),
          const SizedBox(height: 14),

          // [내일 복용약]
          _PillList(title: '내일 복용약', items: const [
            _PillItem(name: '암로디핀 5mg · 아침', status: 0),
            _PillItem(name: '메트포르민 500mg · 아침/점심/저녁', status: 0),
            _PillItem(name: '아스피린 100mg · 아침', status: 0),
          ]),
          const SizedBox(height: 14),

          // [생체 신호 상태]
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: kGreenLight, borderRadius: BorderRadius.circular(14)),
                  child: const Center(child: Text('💚', style: TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('생체 신호', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
                    Text('오늘 측정 완료 · 정상 범위', style: TextStyle(fontSize: 12, color: kGreen)),
                  ],
                )),
                const Icon(Icons.chevron_right_rounded, color: kTextSub),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientChip extends StatelessWidget {
  final String name; final String emoji; final bool isSelected; final VoidCallback onTap;
  const _PatientChip({required this.name, required this.emoji, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryLight : kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isSelected ? kPrimary : kBorder, width: isSelected ? 2 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 4),
            Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kText)),
          ],
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_rounded, size: 28, color: kTextSub),
          const SizedBox(height: 4),
          Text('추가', style: TextStyle(fontSize: 11, color: kTextSub)),
        ],
      ),
    );
  }
}

class _PillItem {
  final String name; final int status; // 1=완료, -1=미완료, 0=예정
  const _PillItem({required this.name, required this.status});
}

class _PillList extends StatelessWidget {
  final String title; final String? badge; final Color? badgeColor; final List<_PillItem> items;
  const _PillList({required this.title, this.badge, this.badgeColor, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kText)),
              if (badge != null) Text(badge!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: badgeColor)),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(item.name, style: const TextStyle(fontSize: 13, color: kText))),
                if (item.status == 1) const Icon(Icons.check_circle_rounded, color: kPrimary, size: 20),
                if (item.status == -1) const Icon(Icons.cancel_rounded, color: kPink, size: 20),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
