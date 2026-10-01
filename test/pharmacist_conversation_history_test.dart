import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/features/drug_explain/conversation_store.dart';
import 'package:alkong_yakong/features/drug_explain/drug_explain_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MvpSession.userId = 'history-user';
    MvpSession.latestOcrItems = [];
  });

  test(
    'history survives a new store and stays separate for each user',
    () async {
      final store = PharmacistConversationStore();
      await store.save('A', {
        'id': '1',
        'updatedAt': '2026-10-02T10:00:00',
        'messages': [],
      });
      await store.save('B', {
        'id': '2',
        'updatedAt': '2026-10-02T11:00:00',
        'messages': [],
      });
      await store.save('A', {
        'id': '1',
        'updatedAt': '2026-10-02T12:00:00',
        'messages': ['updated'],
      });
      final restored = await PharmacistConversationStore().load('A');
      expect(restored, hasLength(1));
      expect(restored.single['messages'], ['updated']);
      expect((await store.load('B')).single['id'], '2');
      expect(await store.load(''), isEmpty);
    },
  );

  testWidgets('save, reopen, preview sources and continue with history', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      Object result = {'medicines': []};
      if (request.method == 'POST') {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        result = {
          'reply': '테스트약정은 음주 시 주의하세요.',
          'sources': ['식약처 의약품 허가정보'],
          'conversation_medicines': [
            {'medicine_code': '202400001', 'product_name': '테스트약정'},
          ],
          'resolved_message': requests.last['message'],
          'resolved_intent': 'precautions',
        };
      }
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = ApiClient(client: client);
    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(
          home: DrugExplainScreen(apiClient: api, medicationApiClient: api),
        ),
      );
      await tester.pumpAndSettle();
    }

    await open();
    await tester.enterText(find.byType(TextField).last, '테스트약정 주의사항은?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(
      await PharmacistConversationStore().load('history-user'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await open();
    await tester.tap(find.text('이전 대화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('테스트약정 주의사항은?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('식약처 의약품 허가정보'), findsOneWidget);
    expect(find.text('당시 정보 기준'), findsNothing);
    expect(find.textContaining(RegExp(r'\d{4}\.\d{2}\.\d{2}')), findsWidgets);
    await tester.tap(find.text('이어서 대화하기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '그럼 술은?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    final history = requests.last['recent_history'] as List;
    expect(history, hasLength(2));
    expect(history.first['role'], 'user');
    expect(history.last['medicines'].single['medicine_code'], '202400001');
    expect(requests.last.containsKey('sources'), isFalse);
    final records = await PharmacistConversationStore().load('history-user');
    expect(records, hasLength(1));
    expect(records.single['messages'], hasLength(4));
    expect(tester.takeException(), isNull);
  });

  for (final all in [false, true]) {
    testWidgets(
      'restore ${all ? 'all' : 'searched'} medicine scope without registration',
      (tester) async {
        await PharmacistConversationStore().save('history-user', {
          'id': 'stored',
          'title': '저장된 질문',
          'updatedAt': '2026-10-02T10:00:00',
          'allMedicines': all,
          'selected': all
              ? []
              : [
                  {
                    'name': '검색약정',
                    'product_name': '검색약정',
                    'medicine_code': '202400001',
                  },
                ],
          'temporary': [
            {'item_name': '검색약정', 'item_seq': '202400001'},
          ],
          'messages': [
            {
              'isMe': true,
              'text': '주의할 점은?',
              'createdAt': '2026-10-02T10:00:00',
            },
            {
              'isMe': false,
              'text': '검색약정의 주의사항입니다.',
              'createdAt': '2026-10-02T10:00:01',
              'conversationMedicines': [
                {'medicine_code': '202400001', 'product_name': '검색약정'},
              ],
            },
          ],
        });
        Map<String, dynamic>? sent;
        final client = MockClient((request) async {
          if (request.method == 'POST') {
            expect(request.url.path, '/api/v1/drug-explain/chat');
            sent = jsonDecode(request.body) as Map<String, dynamic>;
          }
          return http.Response(
            jsonEncode(
              request.method == 'POST'
                  ? {'reply': '새로 확인한 답변입니다.'}
                  : {'medicines': []},
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        final api = ApiClient(client: client);
        await tester.pumpWidget(
          MaterialApp(
            home: DrugExplainScreen(apiClient: api, medicationApiClient: api),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('이전 대화'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('저장된 질문'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('이어서 대화하기'));
        await tester.pumpAndSettle();
        expect(find.text(all ? '약 전체' : '검색약정'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, '그럼 술은?');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();
        expect(sent!['recent_history'], hasLength(2));
        if (all) {
          expect(
            sent!['temporary_medicines'].single['medicine_code'],
            '202400001',
          );
          expect(sent!.containsKey('selected_medicine'), isFalse);
        } else {
          expect(sent!['selected_medicine']['medicine_code'], '202400001');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
