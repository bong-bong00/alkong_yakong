import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/rounded_gradient_app_bar.dart';
import 'patient_data.dart';

/// 환자·보호자 공용 복약기록 화면.
/// - 환자: 본인 기록 (accent = kPrimary, records 생략 → 데모)
/// - 보호자: 선택된 환자 기록 (accent = kGuardian, records·patientName 전달)
/// 날짜 목록 → 누르면 아침/점심/저녁별 복용 여부 + 시각 + 그때 심박이 펼쳐진다.
/// 위치: lib/features/dashboard/presentation/screens/medication_record_screen.dart
class MedicationRecordScreen extends StatefulWidget {
  final Color accent;
  final String? patientName; // 보호자가 볼 때 환자 이름. 환자 본인은 null.
  final bool showBack; // push로 열릴 때 true → 뒤로가기 버튼 표시 (탭일 땐 false)
  final List<DayRecord>? records; // 환자별 기록. null이면 내장 데모 사용.

  const MedicationRecordScreen({
    super.key,
    this.accent = kPrimary,
    this.patientName,
    this.showBack = false,
    this.records,
  });

  @override
  State<MedicationRecordScreen> createState() => _MedicationRecordScreenState();
}

class _MedicationRecordScreenState extends State<MedicationRecordScreen> {
  int? _openIndex = 0; // 펼쳐진 날짜 (기본: 오늘)

  static const _amber = Color(0xFFE6A100);

  // 보호자가 records를 넘기면 그걸, 아니면(환자 본인) 내장 데모를 쓴다.
  List<DayRecord> get _days => widget.records ?? _demoDays;

  // TODO: 백엔드 복약기록 API로 교체. 환자 본인 화면용 데모 데이터.
  final List<DayRecord> _demoDays = const [
    DayRecord('6월 5일 (오늘)', [
      Slot('아침', taken: true, time: '08:10', hr: 76, meds: ['혈압약', '당뇨약']),
      Slot('점심', taken: true, time: '12:04', hr: 80, meds: ['혈압약']),
      Slot('저녁', taken: false, meds: ['혈압약', '당뇨약']),
    ]),
    DayRecord('6월 4일', [
      Slot('아침', taken: true, time: '08:02', hr: 74, meds: ['혈압약', '당뇨약']),
      Slot('점심', taken: true, time: '12:20', hr: 78, meds: ['혈압약']),
      Slot('저녁', taken: true, time: '18:30', hr: 75, meds: ['혈압약', '당뇨약']),
    ]),
    DayRecord('6월 3일', [
      Slot('아침', taken: true, time: '08:15', hr: 77, meds: ['혈압약', '당뇨약']),
      Slot('점심', taken: true, time: '12:10', hr: 79, meds: ['혈압약']),
      Slot('저녁', taken: false, meds: ['혈압약', '당뇨약']),
    ]),
    DayRecord('6월 2일', [
      Slot('아침', taken: true, time: '08:05', hr: 73, meds: ['혈압약', '당뇨약']),
      Slot('점심', taken: true, time: '12:00', hr: 76, meds: ['혈압약']),
      Slot('저녁', taken: true, time: '18:40', hr: 74, meds: ['혈압약', '당뇨약']),
    ]),
    DayRecord('6월 1일', [
      Slot('아침', taken: true, time: '08:12', hr: 75, meds: ['혈압약', '당뇨약']),
      Slot('점심', taken: true, time: '12:08', hr: 77, meds: ['혈압약']),
      Slot('저녁', taken: true, time: '18:25', hr: 76, meds: ['혈압약', '당뇨약']),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: RoundedGradientAppBar(
        '복약 기록',
        color: accent,
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          if (widget.patientName != null) ...[
            Text(
              '${widget.patientName}님의 복약 기록',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: kText,
              ),
            ),
            const SizedBox(height: 14),
          ],
          for (int i = 0; i < _days.length; i++) ...[
            _dayCard(i, _days[i], accent),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _dayCard(int index, DayRecord day, Color accent) {
    final total = day.slots.length;
    final taken = day.slots.where((s) => s.taken).length;
    final allOk = taken == total;
    final open = _openIndex == index;

    final Color statusColor = allOk ? accent : _amber;
    final String summary = allOk ? '복약 완료' : '$taken/$total 복용';

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── 헤더 (탭하면 펼침/접힘) ──
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _openIndex = open ? null : index),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    allOk ? Icons.check_circle_rounded : Icons.error_rounded,
                    color: statusColor,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      day.date,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kText,
                      ),
                    ),
                  ),
                  Text(
                    summary,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: allOk ? Colors.grey[600] : _amber,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── 상세 (아침/점심/저녁) ──
          if (open) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: Column(
                children: [for (final s in day.slots) _slotRow(s, accent)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _slotRow(Slot s, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 시간대 라벨
          SizedBox(
            width: 38,
            child: Text(
              s.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 복용 여부 점
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              s.taken ? Icons.check_circle : Icons.cancel,
              size: 18,
              color: s.taken ? accent : _amber,
            ),
          ),
          const SizedBox(width: 10),
          // 약 이름 + 상태
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.meds.join(' · '),
                  style: const TextStyle(fontSize: 13.5, color: kText),
                ),
                const SizedBox(height: 2),
                Text(
                  s.taken ? '${s.time} 복용 · 심박 ${s.hr} bpm' : '복용 안 함',
                  style: TextStyle(
                    fontSize: 12,
                    color: s.taken ? Colors.grey[500] : _amber,
                    fontWeight: s.taken ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // 심박 강조 (복용 시)
          if (s.taken && s.hr != null) ...[
            const SizedBox(width: 8),
            Row(
              children: [
                const Text('💓', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 3),
                Text(
                  '${s.hr}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
