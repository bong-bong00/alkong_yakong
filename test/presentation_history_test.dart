import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/features/dashboard/application/medication_history_provider.dart';
import 'package:alkong_yakong/core/session/presentation_history.dart';

void main() {
  test(
    'history API is read-only and September fixtures survive unavailable server',
    () async {
      final client = ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, contains('/medication-history'));
          return http.Response('unavailable', 503);
        }),
      );
      final result = await fetchMedicationHistory(
        PresentationHistory.userId,
        apiClient: client,
      );
      expect(result.length, 7);
      expect(result[DateTime(2026, 9, 23)]?.missedSlots, ['점심']);
      await expectLater(
        fetchMedicationHistory('other-user', apiClient: client),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'calendar fixtures survive unavailable server only for target September',
    () async {
      final client = ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          return http.Response('unavailable', 503);
        }),
      );
      final result = await PresentationHistory.fetchCalendar(
        PresentationHistory.userId,
        2026,
        9,
        api: client,
      );
      expect((result['days'] as List)[20]['slots'].length, 3);
      await expectLater(
        PresentationHistory.fetchCalendar('other-user', 2026, 9, api: client),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        PresentationHistory.fetchCalendar(
          PresentationHistory.userId,
          2026,
          10,
          api: client,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test('exact target only and fixed 21 schedules, 19 completed, 2 missed', () {
    expect(PresentationHistory.applies(PresentationHistory.userId), isTrue);
    expect(PresentationHistory.applies('someone-else'), isFalse);
    final rows = PresentationHistory.schedules;
    expect(rows.length, 21);
    expect(rows.where((r) => r['taken'] == true).length, 19);
    expect(
      rows
          .where((r) => r['taken'] == false)
          .map((r) => '${r['date']} ${r['slot']}'),
      ['2026-09-23 점심', '2026-09-26 저녁'],
    );
    for (final row in rows) {
      expect(row['date'].toString(), startsWith('2026-09-2'));
      if (row['taken'] == true) {
        expect(
          row['taken_at'].toString(),
          startsWith('${row['date']}T${row['time']}'),
        );
      } else {
        expect(row['taken_at'], isNull);
      }
    }
  });
  test(
    'calendar preserves real slots and inserts fixtures only in September',
    () {
      final real = {
        'days': [
          {
            'day': 21,
            'slots': [
              {'slot': '아침', 'taken': false},
            ],
            'mark': 'missed',
          },
        ],
      };
      final calendar = PresentationHistory.mergeCalendar(
        PresentationHistory.userId,
        2026,
        9,
        real,
      );
      expect(
        (calendar['days'] as List)[20]['slots'],
        (real['days'] as List).first['slots'],
      );
      expect((calendar['days'] as List)[22]['mark'], 'missed');
      expect(
        PresentationHistory.mergeCalendar(
          PresentationHistory.userId,
          2026,
          10,
          real,
        ),
        real,
      );
      expect(PresentationHistory.mergeCalendar('other', 2026, 9, real), real);
      expect(
        PresentationHistory.mergeCalendar(
          PresentationHistory.userId,
          2026,
          9,
          calendar,
        ),
        calendar,
      );
    },
  );
  test('history counts and prescription remain synthetic and idempotent', () {
    final rows = PresentationHistory.mergeHistory(
      PresentationHistory.userId,
      [],
    );
    expect(rows.fold<int>(0, (n, r) => n + (r['total'] as int)), 21);
    expect(rows.fold<int>(0, (n, r) => n + (r['taken'] as int)), 19);
    expect(
      PresentationHistory.mergeHistory(PresentationHistory.userId, rows),
      rows,
    );
    final real = [
      {'date': '2026-09-21', 'total': 1, 'taken': 0},
    ];
    expect(
      PresentationHistory.mergeHistory(PresentationHistory.userId, real).first,
      real.first,
    );
    expect(PresentationHistory.prescription['status'], 'EXPIRED');
    expect(
      PresentationHistory.prescription['marker'],
      PresentationHistory.marker,
    );
    expect(
      PresentationHistory.includesDay(
        PresentationHistory.userId,
        DateTime(2026, 10, 5),
      ),
      isFalse,
    );
  });
}
