import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alkong_yakong/features/drug_explain/answer_cache.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('canonical context ignores map key order, preserves drug scope', () {
    expect(
      PharmacistAnswerCache.canonical({'b': 2, 'a': 1}),
      PharmacistAnswerCache.canonical({'a': 1, 'b': 2}),
    );
    expect(
      PharmacistAnswerCache.canonical(['drug1']),
      isNot(PharmacistAnswerCache.canonical(['drug1', 'drug2'])),
    );
  });
  test(
    'reuse requires matching question, user, health and medication context',
    () async {
      final cache = PharmacistAnswerCache();
      await cache.save('alice', 'question', 'health1-drugs1', {
        'reply': '확인된 안내',
        'sources': ['식약처'],
      });
      expect(
        await cache.find(
          'alice',
          'question',
          context: 'health1-drugs1',
          maxAge: const Duration(minutes: 15),
        ),
        isNotNull,
      );
      expect(await cache.find('bob', 'question'), isNull);
      expect(await cache.find('alice', 'new question'), isNull);
      expect(
        await cache.find('alice', 'question', context: 'health2-drugs1'),
        isNull,
      );
      expect(
        await cache.find('alice', 'question', context: 'health1-drugs2'),
        isNull,
      );
      expect(
        await cache.find(
          'alice',
          'question',
          maxAge: const Duration(minutes: 15),
          now: DateTime.now().add(const Duration(days: 1)),
        ),
        isNull,
      );
      // Expired or changed contexts remain available only as historical answers.
      expect(await cache.find('alice', 'question'), isNotNull);
    },
  );
  test(
    'ungrounded failure is not stored; corrupted storage is tolerated',
    () async {
      final cache = PharmacistAnswerCache();
      await cache.save('alice', 'question', 'context', {
        'reply': '실패',
        'sources': [],
      });
      expect(await cache.find('alice', 'question'), isNull);
      SharedPreferences.setMockInitialValues({
        'pharmacist_answers_v1_alice': '{broken',
      });
      expect(await cache.find('alice', 'question'), isNull);
    },
  );
}
