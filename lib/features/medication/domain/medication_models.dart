/// 복약 도메인 모델.
///
/// 문구 규칙: 의료 용어를 쓰지 않는다.
/// 복약 완료 → "다 드셨어요", 미복약 → "아직 안 드셨어요".
library;

/// 하루 세 번의 복약 시간대.
enum DoseSlot {
  morning('아침', 8),
  lunch('점심', 12),
  dinner('저녁', 18);

  const DoseSlot(this.label, this.hour);

  /// "아침" / "점심" / "저녁".
  final String label;

  /// 24시간제 기준 시각.
  final int hour;

  /// "아침 8시" / "저녁 6시" — 화면에 그대로 쓰는 큰 시각 문구.
  String get spokenTime {
    final display = hour > 12 ? hour - 12 : hour;
    return '$label $display시';
  }

  /// "오후 6시 2분" 형태의 절대시간. **상대시간("15분 전")은 쓰지 않는다.**
  static String absoluteTime(DateTime time) {
    final isAfternoon = time.hour >= 12;
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final period = isAfternoon ? '오후' : '오전';
    return '$period $hour12시 ${time.minute}분';
  }

  DateTime todayAt(DateTime now) =>
      DateTime(now.year, now.month, now.day, hour);
}

/// 약 한 가지.
class Medicine {
  /// 성분명 — "메트포르민 500mg". 3a에서는 이것이 약 행의 제목이다.
  final String ingredient;

  /// "1알".
  final String amount;

  /// 생김새 — "흰색 동그란 알약".
  /// 3a는 약 사진을 쓰지 않으므로 화면에 크게 띄우지 않고,
  /// 음성 안내([5d])와 스크린리더 설명에만 쓴다.
  final String? appearance;

  /// 어르신용 쉬운 분류 — "혈압약". 화면에 `이름 (분류)` 로 붙인다.
  final String? easyCategory;

  /// 오늘 스케줄 id — 「먹었어요」 서버 기록용.
  final int? scheduleId;

  const Medicine({
    required this.ingredient,
    required this.amount,
    this.appearance,
    this.easyCategory,
    this.scheduleId,
  });

  /// 홈·목록에 쓰는 한 줄 — "암로디핀 5mg (혈압약)".
  String get displayName {
    final category = easyCategory?.trim();
    if (category == null || category.isEmpty) return ingredient;
    return '$ingredient ($category)';
  }

  /// 음성으로 읽어줄 때의 한 줄 — "메트포르민 500mg, 흰색 동그란 알약 1알".
  String get spoken => appearance == null
      ? '$displayName $amount'
      : '$displayName, $appearance $amount';
}

/// 한 시간대의 복약 상태.
class DoseEntry {
  final DoseSlot slot;
  final List<Medicine> medicines;
  final bool taken;

  /// 기록된 절대 시각. 되돌리면 다시 null이 된다.
  final DateTime? takenAt;

  /// "30분 뒤에 다시" 를 눌러 사다리가 밀린 시각.
  final DateTime? snoozedUntil;

  const DoseEntry({
    required this.slot,
    required this.medicines,
    this.taken = false,
    this.takenAt,
    this.snoozedUntil,
  });

  /// "두 알" — 개수를 한글로 읽어준다.
  String get countPhrase {
    const words = ['', '한', '두', '세', '네', '다섯', '여섯'];
    final count = medicines.length;
    if (count < words.length) return '${words[count]} 알';
    return '$count알';
  }

  DoseEntry copyWith({
    bool? taken,
    DateTime? takenAt,
    DateTime? snoozedUntil,
    bool clearTakenAt = false,
    bool clearSnooze = false,
  }) {
    return DoseEntry(
      slot: slot,
      medicines: medicines,
      taken: taken ?? this.taken,
      takenAt: clearTakenAt ? null : (takenAt ?? this.takenAt),
      snoozedUntil: clearSnooze ? null : (snoozedUntil ?? this.snoozedUntil),
    );
  }
}

/// "먹었어요"를 눌렀을 때의 결과.
enum DoseCheckOutcome {
  /// 정상 기록.
  recorded,

  /// 이미 기록된 시간대 — 5f 중복 복용 차단 시트를 띄운다.
  alreadyTaken,

  /// 복약 시각에서 4시간 이상 지남 — 지연 복약 시트를 띄운다.
  tooLate,
}

/// 오늘 하루 전체 상태.
class TodayMedication {
  final List<DoseEntry> doses;

  /// 함께 보는 가족. 이름만 쓰고 관계는 앞에 붙인다 — "딸 지안".
  final String guardianRelation;
  final String guardianName;

  final int heartRate;
  final bool heartRateNormal;

  const TodayMedication({
    required this.doses,
    required this.guardianRelation,
    required this.guardianName,
    required this.heartRate,
    required this.heartRateNormal,
  });

  /// "딸 지안 님".
  String get guardianTitle => '$guardianRelation $guardianName 님';

  int get takenCount => doses.where((d) => d.taken).length;

  bool get allTaken => takenCount == doses.length;

  /// 아직 안 드신 첫 시간대. 다 드셨으면 null.
  DoseEntry? get nextDose {
    for (final dose in doses) {
      if (!dose.taken) return dose;
    }
    return null;
  }

  DoseEntry doseOf(DoseSlot slot) =>
      doses.firstWhere((d) => d.slot == slot);

  /// "아침·점심 다 드셨어요" — 완료 요약 카드 문구.
  String get takenSummary {
    final done = doses.where((d) => d.taken).map((d) => d.slot.label).toList();
    if (done.isEmpty) return '아직 드신 약이 없어요';
    if (allTaken) return '오늘 약 다 드셨어요';
    return '${done.join('·')} 다 드셨어요';
  }

  TodayMedication copyWith({List<DoseEntry>? doses}) => TodayMedication(
    doses: doses ?? this.doses,
    guardianRelation: guardianRelation,
    guardianName: guardianName,
    heartRate: heartRate,
    heartRateNormal: heartRateNormal,
  );
}
