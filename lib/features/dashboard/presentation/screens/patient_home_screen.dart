import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

// ════════════════════════════════════════════════════
//  [환자홈] 박스 4개 세로 배치 화면
// ════════════════════════════════════════════════════
class PatientHomeScreen extends StatelessWidget {
  const PatientHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // [환자홈-여백] 화면 가장자리 여백. 순서: 좌, 상, 우, 하
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        children: [
          // [박스1-복약스케줄]
          const Expanded(
            flex: 5,
            child: MedicationScheduleCard(),
          ),
          // [박스간격-1]
          const SizedBox(height: 16),

          // [박스2-상호작용가이드]
          Expanded(
            flex: 2,
            child: Row(
              children: const [
                Expanded(child: InteractionCard()),
                // [상호작용가이드-사이간격]
                SizedBox(width: 16),
                Expanded(child: GuideCard()),
              ],
            ),
          ),
          // [박스간격-2]
          const SizedBox(height: 16),

          // [박스3-지도]
          const Expanded(
            flex: 3,
            child: MapCard(),
          ),
        ],
      ),
    );
  }
}

// [복약스케줄카드] 오늘 먹을 약 목록
class MedicationScheduleCard extends StatelessWidget {
  const MedicationScheduleCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // [복약카드-내부여백]
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        // [복약카드-모서리]
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            // [수정] withOpacity 대신 withValues 사용
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // [복약카드-항목배치]
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            children: const [
              Icon(Icons.medication, color: kPrimary, size: 24),
              SizedBox(width: 8),
              Text(
                '오늘의 복약 스케줄',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          const MedItem(time: '오전 8:00', pills: '혈압약, 아스피린', done: true),
          const Divider(height: 1),
          const MedItem(time: '오후 12:00', pills: '소화제', done: false),
          const Divider(height: 1),
          const MedItem(time: '오후 8:00', pills: '혈압약, 비타민D', done: false),
        ],
      ),
    );
  }
}

// [복약항목] 복약 스케줄 카드 안의 약 한 줄
class MedItem extends StatelessWidget {
  final String time;
  final String pills;
  final bool done;

  const MedItem({super.key, required this.time, required this.pills, required this.done});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // [복약항목-체크아이콘]
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? kPrimary : Colors.grey[400],
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                time,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 2),
              Text(
                pills,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: done ? Colors.grey : const Color(0xFF2D3748),
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
        // [복약항목-완료뱃지]
        if (done)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kPrimaryLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '완료',
              style: TextStyle(
                color: kPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

// [상호작용카드]
class InteractionCard extends StatelessWidget {
  const InteractionCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange[600], size: 22),
          const SizedBox(height: 6),
          const Text(
            '상호작용 확인',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
          ),
          const SizedBox(height: 4),
          Text(
            '주의 1건',
            style: TextStyle(fontSize: 12, color: Colors.orange[700], fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// [가이드카드]
class GuideCard extends StatelessWidget {
  const GuideCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kPrimaryLight,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.help_outline, color: kPrimary, size: 22),
          SizedBox(height: 6),
          Text(
            '앱 사용 가이드',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
          ),
          SizedBox(height: 4),
          Text(
            '처음이세요?',
            style: TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// [지도카드]
class MapCard extends StatelessWidget {
  const MapCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Container(
              color: const Color(0xFFE8EDF2),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map_outlined, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      '주변 약국 지도',
                      style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_pharmacy, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      '근처 약국',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}