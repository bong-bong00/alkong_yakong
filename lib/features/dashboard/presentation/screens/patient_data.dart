/// 보호자가 모니터링하는 환자 한 명의 전체 데이터.
/// 현황·복약기록·알림·실시간 심박이 모두 이 모델을 공유한다.
/// TODO: 백엔드 연동 시 이 클래스를 API 응답으로 채운다.
/// 위치: lib/features/dashboard/presentation/screens/patient_data.dart
library;

class PatientData {
  final String name;
  final String relation; // 어머니/아버지 등
  /// 아바타에 쓰는 이름 첫 글자. 이모지는 쓰지 않는다.
  final String initial;
  final int age;

  // 현황
  final int takenCount; // 오늘 복용한 횟수
  final int totalCount; // 오늘 총 횟수
  final String nextDose; // 다음에 드실 약 안내
  final int currentHr; // 현재 심박
  final bool hrNormal; // 심박 정상 여부
  final bool okToday; // 오늘 이상 없음 여부
  final String syncedAgo; // 마지막 최신 정보 시각

  final List<ActivityItem> activities; // 최근 활동
  final List<DayRecord> records; // 복약 기록 (날짜별)
  final List<AlertItem> alerts; // 알림

  const PatientData({
    required this.name,
    required this.relation,
    required this.initial,
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

/// 아직 수락하지 않은 초대.
///
/// 초대를 보냈다고 현황이 열리지는 않는다. 어르신이 수락해야 열린다 —
/// 동의 없이 남의 복약을 들여다보는 길을 만들지 않는다.
class PendingInvite {
  final String name;
  final String relation;
  final String phone;
  const PendingInvite({
    required this.name,
    required this.relation,
    required this.phone,
  });
}

class ActivityItem {
  final String text;

  /// 절대시간 문자열. **상대시간("15분 전")은 쓰지 않는다.**
  final String time;
  const ActivityItem(this.text, this.time);
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
  /// 'miss'·'alert' 위험 · 'refill' 약 떨어짐 · 'shared' 어르신이 보냄 ·
  /// 'done' 복약 완료 · 'prescription' 새 처방전 · 'past' 지난 것.
  final String type;
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
  static const List<PatientData> all = [_bokja, _cheolsu, _yeongsuk];

  /// 아직 수락을 기다리는 초대.
  static const List<PendingInvite> pending = [
    PendingInvite(name: '이순자', relation: '이모', phone: '010-2233-****'),
  ];

  static const PatientData _bokja = PatientData(
    name: '김복자',
    relation: '어머니',
    initial: '복',
    age: 72,
    takenCount: 2,
    totalCount: 3,
    nextDose: '저녁 6시 약',
    currentHr: 78,
    hrNormal: true,
    okToday: true,
    syncedAgo: '방금 전',
    activities: [
      ActivityItem('점심 약 다 드셨어요', '12:04'),
      ActivityItem('약 드신 뒤 심장 박동 정상 (80)', '12:14'),
      ActivityItem('아침 약 다 드셨어요', '08:10'),
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
        type: 'miss',
        title: '약을 안 드셨어요',
        desc: '어머니가 저녁 약을 드시지 않았어요',
        time: '어제 저녁',
      ),
      AlertItem(
        type: 'refill',
        title: '약이 떨어졌어요',
        desc: '아스피린 처방이 오늘로 끝났어요',
        time: '방금',
      ),
      AlertItem(
        type: 'shared',
        title: '어머니가 보냈어요',
        desc: '아스피린·와파린 함께먹기 주의를 확인해 달래요',
        time: '11:20',
      ),
      AlertItem(
        type: 'prescription',
        title: '새 처방전',
        desc: '약 3가지가 새로 등록됐어요',
        time: '어제',
      ),
      AlertItem(
        type: 'past',
        title: '심박수',
        desc: '일주일 동안 모두 정상이었어요',
        time: '3일 전',
      ),
      AlertItem(
        type: 'alert',
        title: '심장 박동이 빨라요',
        desc: '김복자 님의 심장 박동이 분당 125회까지 올랐어요',
        time: '14:16',
        tappable: true,
      ),
      AlertItem(
        type: 'done',
        title: '약 다 드셨어요',
        desc: '김복자 님이 점심 약을 다 드셨어요 (심장 박동 80)',
        time: '12:04',
      ),
      AlertItem(
        type: 'miss',
        title: '확인이 필요해요',
        desc: '6월 3일 저녁 약을 드시지 않았어요',
        time: '어제',
      ),
    ],
  );

  static const PatientData _cheolsu = PatientData(
    name: '김철수',
    relation: '아버지',
    initial: '철',
    age: 75,
    takenCount: 3,
    totalCount: 3,
    nextDose: '오늘 약 다 드셨어요',
    currentHr: 68,
    hrNormal: true,
    okToday: true,
    syncedAgo: '5분 전',
    activities: [
      ActivityItem('저녁 약 다 드셨어요', '18:20'),
      ActivityItem('점심 약 다 드셨어요', '12:30'),
      ActivityItem('약 드신 뒤 심장 박동 정상 (70)', '12:40'),
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
        title: '약 다 드셨어요',
        desc: '김철수 님이 저녁 약을 다 드셨어요',
        time: '18:20',
      ),
      AlertItem(
        type: 'done',
        title: '약 다 드셨어요',
        desc: '김철수 님이 점심 약을 다 드셨어요 (심장 박동 70)',
        time: '12:30',
      ),
      AlertItem(
        type: 'done',
        title: '약 다 드셨어요',
        desc: '김철수 님이 아침 약을 다 드셨어요',
        time: '07:50',
      ),
    ],
  );

  static const PatientData _yeongsuk = PatientData(
    name: '박영숙',
    relation: '장모님',
    initial: '영',
    age: 79,
    takenCount: 1,
    totalCount: 3,
    nextDose: '점심 약',
    currentHr: 74,
    hrNormal: true,
    okToday: false,
    syncedAgo: '1시간 전',
    activities: [
      ActivityItem('아침 약 다 드셨어요', '08:05'),
      ActivityItem('약 드신 뒤 심장 박동 정상 (74)', '08:15'),
    ],
    records: [
      DayRecord('6월 5일 (오늘)', [
        Slot('아침', taken: true, time: '08:05', hr: 74, meds: ['혈압약']),
        Slot('점심', taken: false, meds: ['혈압약', '골다공증약']),
        Slot('저녁', taken: false, meds: ['혈압약']),
      ]),
      DayRecord('6월 4일', [
        Slot('아침', taken: true, time: '08:00', hr: 73, meds: ['혈압약']),
        Slot('점심', taken: true, time: '12:40', hr: 76, meds: ['혈압약', '골다공증약']),
        Slot('저녁', taken: true, time: '18:25', hr: 72, meds: ['혈압약']),
      ]),
    ],
    alerts: [
      AlertItem(
        type: 'miss',
        title: '약을 안 드셨어요',
        desc: '박영숙 님이 점심 약을 드시지 않았어요',
        time: '13:30',
      ),
      AlertItem(
        type: 'done',
        title: '약 다 드셨어요',
        desc: '박영숙 님이 아침 약을 다 드셨어요 (심장 박동 74)',
        time: '08:05',
      ),
    ],
  );
}
