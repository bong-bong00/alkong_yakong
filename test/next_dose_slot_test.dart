import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 어느 시간대 약을 드실 참인지 고르는 규칙.
///
/// 앞에서부터 고르면 아침을 건너뛰고 점심에 "먹었어요"를 눌러도 아침이
/// 기록된다. 그러면 드신 점심 약은 기록이 없고, 안 드신 아침 약은 드신
/// 것이 되어 두 번 틀린다.
void main() {
  TodayMedication todayWith({
    bool morningTaken = false,
    bool lunchTaken = false,
    bool dinnerTaken = false,
  }) {
    return TodayMedication(
      guardianRelation: '보호자',
      guardianName: '가족',
      doses: [
        DoseEntry(
          slot: DoseSlot.morning,
          medicines: const [Medicine(ingredient: '아침약', amount: '1알')],
          taken: morningTaken,
        ),
        DoseEntry(
          slot: DoseSlot.lunch,
          medicines: const [Medicine(ingredient: '점심약', amount: '1알')],
          taken: lunchTaken,
        ),
        DoseEntry(
          slot: DoseSlot.dinner,
          medicines: const [Medicine(ingredient: '저녁약', amount: '1알')],
          taken: dinnerTaken,
        ),
      ],
    );
  }

  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 2, hour, minute);

  test('아침을 건너뛰고 점심때 누르면 점심이 기록된다', () {
    final today = todayWith();
    expect(today.nextDoseAt(at(12, 10))?.slot, DoseSlot.lunch);
  });

  test('아침·점심을 건너뛰고 저녁때 누르면 저녁이 기록된다', () {
    final today = todayWith();
    expect(today.nextDoseAt(at(19))?.slot, DoseSlot.dinner);
  });

  test('이른 아침에는 아직 아침 약 차례다', () {
    final today = todayWith();
    expect(today.nextDoseAt(at(7))?.slot, DoseSlot.morning);
  });

  test('점심 조금 전에 눌러도 점심으로 본다', () {
    // 11시 30분에 드시는 분이 적지 않다. 가장 가까운 때로 센다.
    expect(todayWith().nextDoseAt(at(11, 30))?.slot, DoseSlot.lunch);
  });

  test('거리가 같으면 앞선 시간대를 둔다', () {
    // 10시는 아침(8시)·점심(12시)에서 똑같이 두 시간이다. 아직 아침 약을
    // 드실 참으로 본다.
    expect(todayWith().nextDoseAt(at(10))?.slot, DoseSlot.morning);
  });

  test('드신 시간대는 고르지 않는다', () {
    final today = todayWith(lunchTaken: true);
    expect(today.nextDoseAt(at(12, 10))?.slot, DoseSlot.morning);
  });

  test('다 드셨으면 없다', () {
    final today = todayWith(
      morningTaken: true,
      lunchTaken: true,
      dinnerTaken: true,
    );
    expect(today.nextDoseAt(at(12)), isNull);
  });
}
