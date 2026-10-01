import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/features/drug_explain/drug_explain_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Response response(Object value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();
    final wheel = find.byType(ListWheelScrollView);
    await tester.drag(wheel, const Offset(0, 600));
    await tester.pumpAndSettle();
    final option = find.descendant(of: wheel, matching: find.text(label));
    for (var index = 0; index < 20 && option.evaluate().isEmpty; index++) {
      await tester.drag(wheel, const Offset(0, -66));
      await tester.pumpAndSettle();
    }
    await tester.tap(option);
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
  }

  Future<void> ask(WidgetTester tester) async {
    final field = find.byType(TextField).last;
    await tester.enterText(field, '같이 먹어도 되나요?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
  }

  setUp(() => MvpSession.userId = 'scope-user');

  testWidgets('복수 선택은 선택한 두 약만 전달한다', (tester) async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return response({'reply': '검사 응답'});
      }
      return response({
        'medicines': [
          for (final index in [1, 2, 3])
            {
              'medicine_code': 'CODE-$index',
              'product_name': '선택약$index정',
              'official_product_name': '선택약$index정',
              'ingredient': '성분$index',
              'status': 'active',
            },
        ],
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DrugExplainScreen(
          apiClient: ApiClient(client: client),
          medicationApiClient: ApiClient(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pick(tester, '약 이름 선택');
    await tester.tap(find.byKey(const ValueKey('medicine-selection-선택약1정')));
    await tester.tap(find.byKey(const ValueKey('medicine-selection-선택약2정')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2개 선택'));
    await tester.pumpAndSettle();
    await ask(tester);
    expect(sent, isNotNull);
    expect(
      (sent!['selected_medicines'] as List).map((m) => m['medicine_code']),
      ['CODE-1', 'CODE-2'],
    );
    expect(sent!.containsKey('selected_medicine'), isFalse);
  });

  testWidgets('임시 검색약은 단일 선택과 약 전체에서 전달된다', (tester) async {
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        return response({'reply': '검사 응답'});
      }
      if (request.url.path.endsWith('/drugs/search')) {
        return response({
          'items': [
            {'item_name': '검색약정', 'item_seq': 'TEMP-1', 'manufacturer': '제조사'},
          ],
        });
      }
      return response({
        'medicines': [
          {
            'medicine_code': 'CODE-1',
            'product_name': '등록약정',
            'official_product_name': '등록약정',
            'ingredient': '성분',
            'status': 'active',
          },
        ],
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DrugExplainScreen(
          apiClient: ApiClient(client: client),
          medicationApiClient: ApiClient(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();
    final wheel = find.byType(ListWheelScrollView);
    await tester.drag(wheel, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('약 이름 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다른 약 검색하기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('otherMedicineSearchField')),
      '검색약',
    );
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();
    await tester.tap(find.text('검색약정'));
    await tester.pumpAndSettle();
    await ask(tester);
    expect(sent.last['selected_medicine']['medicine_code'], 'TEMP-1');
    // 단일 약은 selected_medicine에, 전체·복수 범위의 임시 약은 별도 목록에 전달한다.
    expect(sent.last.containsKey('temporary_medicines'), isFalse);
    await pick(tester, '약 전체');
    await ask(tester);
    expect(sent.last.containsKey('selected_medicine'), isFalse);
    expect(sent.last.containsKey('selected_medicines'), isFalse);
    expect(sent.last['temporary_medicines'][0]['medicine_code'], 'TEMP-1');
    expect(sent.last['user_id'], 'scope-user');
  });
}
