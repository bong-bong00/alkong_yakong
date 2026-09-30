/// 화면 확인용 가짜 데이터. **개발 빌드에서만** 먹는다.
///
/// 서버·로그인 없이 화면을 넘겨 보려고 둔 것이다. 값은 명세서의 보기와
/// 같게 맞췄다 (김복자 · 메트포르민 500mg · 아침 8:10 · 심박 78 → 72).
///
/// 올리기 전에 [kMockData]와 main.dart의 `kSkipLogin`을 false로 되돌린다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'core/network/api_client.dart';
import 'features/biosignal/data/heart_repository.dart';
import 'features/biosignal/domain/heart_data.dart';
import 'features/dashboard/application/medication_history_provider.dart';
import 'features/dashboard/presentation/screens/month_calendar_screen.dart';
import 'features/dashboard/presentation/screens/patient_data.dart';
import 'features/guardian/application/guardians_provider.dart';
import 'features/guardian/data/alert_repository.dart';
import 'features/guardian/data/guardian_repository.dart';
import 'features/guardian/presentation/screens/care_patient_screen.dart';
import 'features/medication/application/medication_controller.dart';
import 'features/medication/domain/medication_models.dart';
import 'features/medicines/application/user_medicines_controller.dart';
import 'features/medicines/domain/user_medicine_models.dart';
import 'features/prescription/presentation/screens/prescription_history_screen.dart';
import 'features/profile/application/current_user_controller.dart';
import 'features/profile/domain/user_profile.dart';

/// 켜면 서버 대신 가짜 데이터로 화면을 채운다.
const bool kMockData = false;

/// 배포 빌드에서는 절대 먹지 않는다.
bool get mockData => kMockData && kDebugMode;

/// 오늘. 시각만 바꿔 쓰므로 한 번만 만든다.
DateTime get _today => DateTime.now();

DateTime _at(int hour, int minute) =>
    DateTime(_today.year, _today.month, _today.day, hour, minute);

// ── 약 ────────────────────────────────────────────────────

const _metformin = Medicine(
  ingredient: '메트포르민 500mg',
  amount: '1알',
  appearance: '흰색 동그란 알약',
  purposeLabel: '혈당 낮추는 약',
  shortExplanation: '몸에서 당을 잘 쓰게 도와 혈당을 낮춰 줍니다.',
  medicineCode: '200701021',
  scheduleId: 101,
  frequencyPerDay: 2,
);

const _amlodipine = Medicine(
  ingredient: '암로디핀 5mg',
  amount: '1알',
  appearance: '노란 길쭉한 알약',
  purposeLabel: '혈압 내리는 약',
  medicineCode: '200701022',
  scheduleId: 102,
  frequencyPerDay: 1,
);

const _aspirin = Medicine(
  ingredient: '아스피린 100mg',
  amount: '1알',
  appearance: '흰색 작은 알약',
  purposeLabel: '피를 묽게 하는 약',
  medicineCode: '200701023',
  scheduleId: 103,
  frequencyPerDay: 1,
);

/// 오늘 하루. 아침은 드셨고, 점심은 없고, 저녁이 남았다 (명세서 31).
TodayMedication _mockToday() => TodayMedication(
  doses: [
    DoseEntry(
      slot: DoseSlot.morning,
      medicines: const [_metformin, _aspirin],
      taken: true,
      takenAt: _at(8, 10),
      // 기록 탭의 "오늘 심박수" 칸은 잰 값이 있을 때만 뜬다.
      heartCheck: DoseHeartCheck(before: 78, after: 72, measuredAt: _at(8, 20)),
    ),
    const DoseEntry(
      slot: DoseSlot.dinner,
      medicines: [_metformin, _amlodipine],
    ),
  ],
  guardianRelation: '딸',
  guardianName: '지안',
  heartRate: 72,
  heartRateNormal: true,
  daysLeft: 3,
  courseStartedOn: _today.subtract(const Duration(days: 18)),
  courseTotalDays: 21,
);

class _MockMedication extends MedicationController {
  _MockMedication() : super(apiClient: _silentApi());

  @override
  TodayMedication build() => _mockToday();

  // 서버에 다시 묻지 않는다 — 가짜 하루를 그대로 둔다.
  @override
  Future<void> refreshFromServer({bool throwOnError = false}) async {}
}

// ── 내 약 목록 ────────────────────────────────────────────

UserMedicine _userMedicine({
  required String code,
  required String name,
  required String ingredient,
  required String purpose,
  String status = 'active',
  List<String> times = const ['아침', '저녁'],
  String explanation = '',
  String highlight = '',
  List<TreatmentUse> uses = const [],
  List<String> cautions = const [],
  String conflictWith = '',
  String conflictWhy = '',
  String maker = '바이엘코리아',
  String strength = '',
  int frequency = 1,
}) => UserMedicine(
  medicineCode: code,
  displayName: name,
  officialProductName: name,
  manufacturer: maker,
  ingredientName: ingredient,
  ingredientStrength: strength,
  dosageForm: '정제',
  amount: '1알',
  frequencyPerDay: frequency,
  status: status,
  purposeLabel: purpose,
  administrationTimes: times,
  detailExplanation: explanation,
  ingredientExplanation: explanation,
  ingredientHighlight: highlight,
  treatmentUses: uses,
  keyCautions: cautions,
  interactionStatus: conflictWith.isEmpty ? 'checked' : 'risk_found',
  interactionSummary: conflictWhy.isEmpty ? null : conflictWhy,
  interactionConflictNames: conflictWith.isEmpty ? const [] : [conflictWith],
  officialUsageNotice: '밥을 드신 뒤에 물을 넉넉히 마시며 드세요.',
  detailStatus: 'READY',
  detailSourceName: '식약처 의약품 허가정보',
);

List<UserMedicine> _mockMedicines() => [
  _userMedicine(
    code: '200701021',
    name: '메트포르민 500mg',
    ingredient: '메트포르민염산염',
    strength: '500mg',
    purpose: '혈당 낮추는 약',
    frequency: 2,
    explanation:
        '몸에서 당을 잘 쓰게 도와 혈당을 낮춰 줍니다. '
        '당뇨약 중에서 가장 오래, 가장 많이 쓰이는 약이에요.',
    highlight: '혈당을 낮춰',
    uses: const [
      TreatmentUse(title: '제2형 당뇨', description: '식사·운동으로 조절이 안 되는 경우'),
      TreatmentUse(title: '다른 당뇨약', description: '과 함께 쓰는 경우'),
    ],
    cautions: const ['속이 불편하면 식사 직후에 드시고, 그래도 불편하면 알려주세요.'],
  ),
  _userMedicine(
    code: '200701022',
    name: '암로디핀 5mg',
    ingredient: '암로디핀베실산염',
    strength: '5mg',
    purpose: '혈압 내리는 약',
    times: const ['저녁'],
    explanation: '혈관을 넓혀 피가 잘 흐르게 해서 혈압을 낮춰 줍니다.',
    highlight: '혈압을 낮춰',
    uses: const [TreatmentUse(title: '고혈압', description: '을 꾸준히 관리할 때')],
  ),
  _userMedicine(
    code: '200701023',
    name: '아스피린 100mg',
    ingredient: '아세틸살리실산',
    strength: '100mg',
    purpose: '피를 묽게 하는 약',
    times: const ['아침'],
    explanation:
        '피가 굳어 혈관을 막는 것을 예방합니다. '
        '심장·뇌를 지키기 위해 매일 드시는 약이에요.',
    highlight: '혈관을 막는 것을 예방',
    uses: const [
      TreatmentUse(title: '심근경색', description: '·뇌경색 재발 예방'),
      TreatmentUse(title: '혈전', description: '이 걱정되는 경우'),
    ],
    conflictWith: '와파린',
    conflictWhy: '두 약 모두 피를 묽게 해서, 같이 드시면 피가 잘 멈추지 않을 수 있어요.',
    cautions: const ['검은색 변이 나오거나, 코피·잇몸 피가 잘 멈추지 않으면 바로 알려주세요.'],
  ),
  _userMedicine(
    code: '200701024',
    name: '타이레놀 500mg',
    ingredient: '아세트아미노펜',
    purpose: '열 내리고 아픈 것을 덜어 주는 약',
    status: 'ended',
    times: const ['아침'],
  ),
  _userMedicine(
    code: '200701025',
    name: '무코스타 100mg',
    ingredient: '레바미피드',
    purpose: '속을 보호하는 약',
    status: 'ended',
    times: const ['점심'],
  ),
];

class _MockUserMedicines extends UserMedicinesController {
  @override
  Future<List<UserMedicine>> build() async => _mockMedicines();

  @override
  Future<void> refresh() async {}

  // 약 자세히도 서버 없이 연다.
  @override
  Future<UserMedicine> loadDetail(String medicineCode) async =>
      _mockMedicines().firstWhere(
        (med) => med.medicineCode == medicineCode,
        orElse: () => _mockMedicines().first,
      );
}

// ── 내 정보 ───────────────────────────────────────────────

class _MockUser extends CurrentUserController {
  @override
  Future<UserProfile?> build() async => UserProfile(
    id: 'mock-patient',
    name: '김복자',
    role: 'patient',
    phone: '010-1234-5678',
    birthDate: DateTime(1958, 4, 3),
    gender: 'female',
    heightCm: 156,
    weightKg: 54,
    bloodType: 'B형',
    smoking: 'never',
    drinking: 'never',
    allergies: const ['페니실린'],
    diseases: const ['고혈압', '당뇨'],
  );
}

// ── 기록 ──────────────────────────────────────────────────

/// 지난 한 달. 16일만 한 번 놓친 것으로 둔다 (명세서 44).
Map<DateTime, DayAdherence> _mockHistory() {
  final map = <DateTime, DayAdherence>{};
  final today = DateTime(_today.year, _today.month, _today.day);
  for (int back = 0; back < 30; back++) {
    final date = today.subtract(Duration(days: back));
    final missed = date.day % 9 == 7;
    map[date] = DayAdherence(
      date: date,
      taken: back == 0 ? 1 : (missed ? 1 : 2),
      total: 2,
      missedSlots: missed ? const ['저녁'] : const [],
    );
  }
  return map;
}

/// 달력 한 달 (명세서 44). 지난 날은 대개 다 드셨고, 아흐레마다 한 번 놓친다.
List<CalendarDay> mockCalendarDays(int year, int month) {
  final last = DateTime(year, month + 1, 0).day;
  final now = DateTime.now();
  final isThisMonth = year == now.year && month == now.month;
  return [
    for (int day = 1; day <= last; day++)
      if (isThisMonth && day == now.day)
        CalendarDay(
          day,
          DayMark.today,
          slots: const [
            CalendarSlot(slot: '아침', taken: true),
            CalendarSlot(slot: '저녁', taken: false),
          ],
        )
      else if (isThisMonth && day > now.day)
        CalendarDay(day, DayMark.future)
      else if (day % 9 == 7)
        CalendarDay(
          day,
          DayMark.missed,
          slots: const [
            CalendarSlot(slot: '아침', taken: true),
            CalendarSlot(slot: '저녁', taken: false),
          ],
        )
      else
        CalendarDay(
          day,
          DayMark.done,
          slots: const [
            CalendarSlot(slot: '아침', taken: true),
            CalendarSlot(slot: '저녁', taken: true),
          ],
        ),
  ];
}

/// 지금까지 넣은 처방전 (화면 확인용).
List<PrescriptionRecord> mockPrescriptionHistory() => [
  PrescriptionRecord(
    date: _today.subtract(const Duration(days: 18)),
    place: '행복한내과의원 · 우리약국',
    medicines: const [
      PrescriptionLine(name: '메트포르민 500mg', days: 30),
      PrescriptionLine(name: '암로디핀 5mg', days: 30),
      PrescriptionLine(name: '아스피린 100mg', days: 30),
    ],
  ),
  PrescriptionRecord(
    date: _today.subtract(const Duration(days: 64)),
    place: '한빛정형외과',
    medicines: const [
      PrescriptionLine(name: '타이레놀 500mg', days: 5),
      PrescriptionLine(name: '무코스타 100mg', days: 5),
    ],
  ),
];

// ── 심박수 ────────────────────────────────────────────────

class _MockHeartRepository extends HeartRepository {
  @override
  Future<HeartData?> fetch({String? userId}) async => HeartData.demo;
}

/// 심박수 화면에 넣어 주는 가짜 저장소. 켜져 있지 않으면 null이다.
HeartRepository? mockHeartRepository() =>
    mockData ? _MockHeartRepository() : null;

// ── 가족 · 보호자 ─────────────────────────────────────────

const _guardians = [
  GuardianContact(
    id: 'mock-guardian-1',
    name: '김지안',
    relation: '딸',
    phone: '010-2345-6789',
  ),
];

const _patients = [
  CarePatient(
    linkId: 'mock-1',
    patientId: 'mock-1',
    name: '김복자',
    relation: '어머니',
    phone: '010-1234-5678',
    age: 68,
    takenCount: 2,
    totalCount: 3,
    nextDoseLabel: '저녁',
    slots: [
      CareSlot('아침', true),
      CareSlot('점심', true),
      CareSlot('저녁 6시', false),
    ],
    heartRate: 72,
    heartRateNormal: true,
    weekRate: 94,
    activities: [
      ActivityItem('점심 약을 드셨어요', '오늘 12:10'),
      ActivityItem('아침 약을 드셨어요', '오늘 08:05'),
    ],
  ),
  CarePatient(
    linkId: 'mock-2',
    patientId: 'mock-2',
    name: '김성호',
    relation: '아버지',
    phone: '010-3456-7890',
    age: 72,
    takenCount: 3,
    totalCount: 3,
    slots: [CareSlot('아침', true), CareSlot('점심', true), CareSlot('저녁', true)],
    heartRate: 68,
    heartRateNormal: true,
    weekRate: 100,
  ),
  CarePatient(
    linkId: 'mock-3',
    patientId: 'mock-3',
    name: '박영자',
    relation: '장모님',
    phone: '010-4567-8901',
    age: 75,
    takenCount: 1,
    totalCount: 2,
    nextDoseLabel: '점심',
    slots: [CareSlot('아침', true), CareSlot('점심', false)],
    heartRate: 75,
    heartRateNormal: true,
    weekRate: 88,
  ),
];

class _MockAlerts implements AlertRepository {
  @override
  Future<List<AlertItem>?> fetch(String userId) async => const [
    AlertItem(
      type: 'miss',
      title: '약을 안 드셨어요',
      desc: '어머니가 저녁 약을 드시지 않았어요',
      time: '어제 저녁',
      tappable: false,
    ),
    AlertItem(
      type: 'done',
      title: '복약 완료',
      desc: '어머니가 점심 약을 드셨어요',
      time: '오늘 12:10',
      tappable: false,
    ),
    AlertItem(
      type: 'prescription',
      title: '새 처방전',
      desc: '약 3가지가 새로 등록됐어요',
      time: '어제',
      tappable: true,
    ),
    AlertItem(
      type: 'past',
      title: '심박수',
      desc: '일주일 동안 모두 정상이었어요',
      time: '3일 전',
      tappable: false,
    ),
  ];
}

/// 보호자 알림 화면에 넣어 주는 가짜 저장소.
AlertRepository? mockAlertRepository() => mockData ? _MockAlerts() : null;

/// 보호자가 보는 어르신 한 사람.
UserProfile _mockPatientProfile(String id) {
  final patient = _patients.firstWhere(
    (p) => p.patientId == id,
    orElse: () => _patients.first,
  );
  return UserProfile(
    id: id,
    name: patient.name,
    role: 'patient',
    phone: patient.phone,
    birthDate: DateTime(_today.year - (patient.age ?? 68), 4, 3),
    gender: patient.name == '김성호' ? 'male' : 'female',
    heightCm: 156,
    weightKg: 54,
    bloodType: 'B형',
    smoking: 'never',
    drinking: 'never',
    allergies: const ['페니실린'],
    diseases: const ['고혈압', '당뇨'],
  );
}

// ── 묶어서 내보내기 ───────────────────────────────────────

/// 서버에 아무것도 보내지 않는 ApiClient. 기록 버튼을 눌러도 조용히 끝난다.
ApiClient _silentApi() => ApiClient(
  client: MockClient(
    (_) async => http.Response(
      '{}',
      200,
      headers: const {'content-type': 'application/json'},
    ),
  ),
);

/// 앱 전체에 가짜 데이터를 깐다. [mockData]가 꺼져 있으면 빈 목록이다.
///
/// [force]는 테스트가 플래그와 상관없이 가짜 데이터를 깔 때만 쓴다.
List<Override> devMockOverrides({bool force = false}) {
  if (!mockData && !force) return const [];
  return [
    medicationProvider.overrideWith(_MockMedication.new),
    userMedicinesProvider.overrideWith(_MockUserMedicines.new),
    currentUserProvider.overrideWith(_MockUser.new),
    guardiansProvider.overrideWith((ref) async => _guardians),
    careOverviewProvider.overrideWith(
      (ref) async => const CareOverview(patients: _patients),
    ),
    medicationHistoryProvider.overrideWith((ref) async => _mockHistory()),
    patientHistoryProvider.overrideWith((ref, id) async => _mockHistory()),
    patientTodayProvider.overrideWith((ref, id) async => _mockToday()),
    patientMedicinesProvider.overrideWith((ref, id) async => _mockMedicines()),
    carePatientProfileProvider.overrideWith(
      (ref, id) async => _mockPatientProfile(id),
    ),
    prescriptionHistoryProvider.overrideWith(
      (ref) async => mockPrescriptionHistory(),
    ),
  ];
}
