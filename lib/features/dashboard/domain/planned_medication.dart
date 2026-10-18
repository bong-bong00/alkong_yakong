class PlannedMedicine {
  final String name;
  final String amount;
  const PlannedMedicine(this.name, this.amount);
}

class PlannedMedicationSlot {
  final String slot;
  final String time;
  final List<PlannedMedicine> medicines;
  const PlannedMedicationSlot({
    required this.slot,
    required this.time,
    required this.medicines,
  });

  static List<PlannedMedicationSlot> parse(dynamic raw) => [
    if (raw is List)
      for (final row in raw)
        if (row is Map && row['medicines'] is List)
          PlannedMedicationSlot(
            slot: row['slot']?.toString() ?? '복약',
            time: _clock(row['time']),
            medicines: [
              for (final medicine in row['medicines'] as List)
                if (medicine is Map)
                  PlannedMedicine(
                    medicine['name']?.toString() ?? '약 이름 확인 필요',
                    medicine['amount']?.toString() ?? '복용량 확인 필요',
                  ),
            ],
          ),
  ];

  static String _clock(dynamic raw) {
    final match = RegExp(
      r'^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$',
    ).firstMatch(raw?.toString() ?? '');
    return match == null ? '시간 확인 필요' : '${match[1]}:${match[2]}';
  }
}
