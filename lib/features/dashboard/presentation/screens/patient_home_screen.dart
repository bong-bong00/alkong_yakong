import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';

class PatientHomeScreen extends StatelessWidget {
  const PatientHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [인사말]
          const Text('안녕하세요 👋', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 2),
          Text('오늘도 건강한 하루 보내세요!', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          const SizedBox(height: 20),

          // [처방전 등록 배너]
          GestureDetector(
            onTap: () => context.push('/prescription'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1D9E75), Color(0xFF25B88A)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(14)),
                    child: const Center(child: Text('📋', style: TextStyle(fontSize: 24))),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('처방전 등록하기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('처방전을 촬영하면 약 정보가 자동 등록돼요', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // [복약 스케줄]
          _SectionTitle(emoji: '💊', title: '오늘의 복약'),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), boxShadow: [_softShadow]),
            child: Column(
              children: [
                _MedTile(time: '아침 8:00', pills: '암로디핀 5mg, 아스피린 100mg', done: true),
                const Divider(height: 1, indent: 56),
                _MedTile(time: '점심 12:00', pills: '메트포르민 500mg', done: true),
                const Divider(height: 1, indent: 56),
                _MedTile(time: '저녁 6:00', pills: '메트포르민 500mg, 암로디핀 5mg', done: false),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // [복약 안전도 + 가이드]
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push('/dur-analysis'),
                  child: _MiniCard(
                    emoji: '🛡️',
                    title: '복약 안전도',
                    value: 'LOW',
                    valueColor: kGreen,
                    bgColor: kGreenLight,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniCard(emoji: '📖', title: '앱 가이드', value: '보기', valueColor: kPrimary, bgColor: kPrimaryLight),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // [생체 신호]
          _SectionTitle(emoji: '❤️', title: '생체 신호'),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => context.push('/biosignal'),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), boxShadow: [_softShadow]),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: kRedLight, borderRadius: BorderRadius.circular(14)),
                    child: const Center(child: Text('💓', style: TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('폴라 베리티 센스', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
                        const SizedBox(height: 2),
                        Text('탭하여 센서를 연결하세요', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
                    child: Text('연결 대기', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // [주변 약국]
          _SectionTitle(emoji: '🏥', title: '주변 약국'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 130,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2F6),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [_softShadow],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map_outlined, size: 36, color: Colors.grey[400]),
                  const SizedBox(height: 6),
                  Text('지도 연동 예정', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════
//  공통 위젯들
// ════════════════════════════════════════════════════

final _softShadow = BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4));

class _SectionTitle extends StatelessWidget {
  final String emoji; final String title;
  const _SectionTitle({required this.emoji, required this.title});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(width: 6),
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
    ]);
  }
}

class _MedTile extends StatelessWidget {
  final String time; final String pills; final bool done;
  const _MedTile({required this.time, required this.pills, required this.done});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: done ? kPrimaryLight : kPinkLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(done ? Icons.check_rounded : Icons.access_time_rounded, color: done ? kPrimary : kPink, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 2),
                Text(pills, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: done ? Colors.grey : kText)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: done ? kPrimaryLight : kPinkLight, borderRadius: BorderRadius.circular(20)),
            child: Text(done ? '완료' : '미복약', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: done ? kPrimary : kPink)),
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String emoji; final String title; final String value; final Color valueColor; final Color bgColor;
  const _MiniCard({required this.emoji, required this.title, required this.value, required this.valueColor, required this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), boxShadow: [_softShadow]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
            child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: valueColor)),
          ),
        ],
      ),
    );
  }
}
