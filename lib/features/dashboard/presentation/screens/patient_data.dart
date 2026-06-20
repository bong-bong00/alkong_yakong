/// 보호자가 모니터링하는 환자 한 명의 전체 데이터.
/// 현황·복약기록·알림·실시간 심박이 모두 이 모델을 공유한다.
/// TODO: 백엔드 연동 시 이 클래스를 API 응답으로 채운다.
/// 위치: lib/features/dashboard/presentation/screens/patient_data.dart
library;

class PatientData {
  final String name;
  final String relation; // 어머니/아버지 등
  final String emoji;
  final int age;

  // 현황
  final int takenCount; // 오늘 복용한 횟수
  final int totalCount; // 오늘 총 횟수
  final String nextDose; // 다음 복약 안내
  final int currentHr; // 현재 심박
  final bool hrNormal; // 심박 정상 여부
  final bool okToday; // 오늘 이상 없음 여부
  final String syncedAgo; // 마지막 동기화

  final List<ActivityItem> activities; // 최근 활동
  final List<DayRecord> records; // 복약 기록 (날짜별)
  final List<AlertItem> alerts; // 알림

  const PatientData({
    required this.name,
    required this.relation,
    required this.emoji,
    required this.age,
    required this.takenCount,
    required this.totalCount,
    required this.nextDose,
    required this.currentHr,
    required this.hrNormal,
    required this.okToday,
    required this.syncedAgo,
    required this.activities,
    required this.records,
    required this.alerts,
  });
}

class ActivityItem {
  final String emoji;
  final String text;
  final String time;
  const ActivityItem(this.emoji, this.text, this.time);
}

class DayRecord {
  final String date;
  final List<Slot> slots;
  const DayRecord(this.date, this.slots);
}

class Slot {
  final String label; // 아침/점심/저녁
  final bool taken;
  final String? time;
  final int? hr;
  final List<String> meds;
  const Slot(
    this.label, {
    required this.taken,
    this.time,
    this.hr,
    this.meds = const [],
  });
}

class AlertItem {
  final String type; // 'alert'(심박) | 'done' | 'miss'
  final String title;
  final String desc;
  final String time;
  final bool tappable; // 심박 이상 → 상세로
  const AlertItem({
    required this.type,
    required this.title,
    required this.desc,
    required this.time,
    this.tappable = false,
  });
}

// ════════════════════════════════════════════════════════════════
//  데모 데이터 — 환자 2명 (서로 다르게)
// ════════════════════════════════════════════════════════════════
class DemoPatients {
  static const List<PatientData> all = [_bokja, _cheolsu];

  static const PatientData _bokja = PatientData(
    name: '김복자',
    relation: '어머니',
    emoji: '🧓',
    age: 72,
    takenCount: 2,
    totalCount: 3,
    nextDose: '저녁 18:00 예정',
    currentHr: 78,
    hrNormal: true,
    okToday: true,
    syncedAgo: '방금 전',
    activities: [
      ActivityItem('✅', '점심 약 복용 완료', '12:04'),
      ActivityItem('💓', '복약 후 심박 정상 (80 bpm)', '12:14'),
      ActivityItem('✅', '아침 약 복용 완료', '08:10'),
    ],
    records: [
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
    ],
    alerts: [
      AlertItem(
        type: 'alert',
        title: '심박 이상 감지',
        desc: '김복자님의 심박이 분당 125회까지 올랐어요 (빈맥)',
        time: '14:16',
        tappable: true,
      ),
      AlertItem(
        type: 'done',
        title: '복약 완료',
        desc: '김복자님이 점심 약을 복용했어요 (심박 80)',
        time: '12:04',
      ),
      AlertItem(
        type: 'miss',
        title: '미복약 알림',
        desc: '6/3 저녁 약을 복용하지 않았어요',
        time: '어제',
      ),
    ],
  );

  static const PatientData _cheolsu = PatientData(
    name: '김철수',
    relation: '아버지',
    emoji: '👴',
    age: 75,
    takenCount: 3,
    totalCount: 3,
    nextDose: '오늘 복약 완료',
    currentHr: 68,
    hrNormal: true,
    okToday: true,
    syncedAgo: '5분 전',
    activities: [
      ActivityItem('✅', '저녁 약 복용 완료', '18:20'),
      ActivityItem('✅', '점심 약 복용 완료', '12:30'),
      ActivityItem('💓', '복약 후 심박 정상 (70 bpm)', '12:40'),
    ],
    records: [
      DayRecord('6월 5일 (오늘)', [
        Slot('아침', taken: true, time: '07:50', hr: 66, meds: ['고지혈증약']),
        Slot('점심', taken: true, time: '12:30', hr: 70, meds: ['고지혈증약', '관절약']),
        Slot('저녁', taken: true, time: '18:20', hr: 68, meds: ['고지혈증약']),
      ]),
      DayRecord('6월 4일', [
        Slot('아침', taken: true, time: '07:55', hr: 67, meds: ['고지혈증약']),
        Slot('점심', taken: false, meds: ['고지혈증약', '관절약']),
        Slot('저녁', taken: true, time: '18:10', hr: 69, meds: ['고지혈증약']),
      ]),
      DayRecord('6월 3일', [
        Slot('아침', taken: true, time: '08:00', hr: 66, meds: ['고지혈증약']),
        Slot('점심', taken: true, time: '12:15', hr: 71, meds: ['고지혈증약', '관절약']),
        Slot('저녁', taken: true, time: '18:05', hr: 68, meds: ['고지혈증약']),
      ]),
    ],
    alerts: [
      AlertItem(
        type: 'done',
        title: '복약 완료',
        desc: '김철수님이 저녁 약을 복용했어요',
        time: '18:20',
      ),
      AlertItem(
        type: 'done',
        title: '복약 완료',
        desc: '김철수님이 점심 약을 복용했어요 (심박 70)',
        time: '12:30',
      ),
      AlertItem(
        type: 'done',
        title: '복약 완료',
        desc: '김철수님이 아침 약을 복용했어요',
        time: '07:50',
      ),
    ],
  );
}
