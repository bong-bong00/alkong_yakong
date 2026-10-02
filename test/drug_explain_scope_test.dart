import 'dart:convert';

import 'package:alkong_yakong/core/polar_pharmacist_ui/constants/app_colors.dart';
import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/features/drug_explain/drug_explain_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  http.Response response(Object value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  /// 머리 아래 칸을 눌러 약 하나를 고른다. 누르면 바로 닫힌다.
  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('ai-subject-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('medicine-selection-$label')));
    await tester.pumpAndSettle();
  }

  /// 고른 약을 뺀다.
  Future<void> clearPick(WidgetTester tester) async {
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
  }

  /// 질문 카드를 누른다. 대화 아래에 있으면 굴려서 꺼낸다.
  Future<void> tapCard(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> ask(WidgetTester tester) async {
    final field = find.byType(TextField).last;
    await tester.enterText(field, '같이 먹어도 되나요?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
  }

  setUp(() {
    MvpSession.userId = 'scope-user';
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('같은 빠른 질문은 로컬 재사용, 최신 조회 실패는 이전 답변 표시', (tester) async {
    var calls = 0;
    var offline = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/cache-context')) {
        return response({'verified': true, 'fingerprint': 'health-v1'});
      }
      if (request.method == 'POST') {
        calls++;
        if (offline) throw http.ClientException('offline');
        return response({
          'reply': '공식 안내를 확인했어요.',
          'sources': ['식약처'],
        });
      }
      return response({
        'medicines': [
          {
            'medicine_code': '202400001',
            'product_name': '약정',
            'official_product_name': '약정',
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
    await pick(tester, '약정');
    await tapCard(tester, '꼭 식사 후에 복용해야 하나요?');
    expect(calls, 1);
    // 약을 뺐다 다시 고르면 대화가 처음으로 돌아간다. 같은 질문을 다시
    // 누르면 서버에 또 묻지 않고 저장해 둔 답을 보여 준다.
    await clearPick(tester);
    await pick(tester, '약정');
    await tapCard(tester, '꼭 식사 후에 복용해야 하나요?');
    expect(calls, 1);
    expect(find.textContaining('저장된 답변 ·'), findsOneWidget);
    offline = true;
    await tester.ensureVisible(find.text('최신 정보 확인'));
    await tester.tap(find.text('최신 정보 확인'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.textContaining('현재 약·건강정보는 다시 확인하지 않았어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('최근 대화 전달과 출처 표시, 약 범위 변경 시 문맥 초기화', (tester) async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return response({
          'reply': '선택약1정의 공식 주의사항을 확인했어요.',
          'sources': requests.length == 1 ? ['식약처 의약품 허가정보'] : [],
          'conversation_medicines': [
            {'medicine_code': '202400001', 'product_name': '선택약1정'},
          ],
          'resolved_message': requests.last['message'],
          'resolved_intent': 'precautions',
        });
      }
      return response({
        'medicines': [
          {
            'medicine_code': '202400001',
            'product_name': '선택약1정',
            'official_product_name': '선택약1정',
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
    await ask(tester);
    expect(requests.single['recent_history'], isEmpty);
    expect(find.text('출처: 식약처 의약품 허가정보'), findsOneWidget);
    final field = find.byType(TextField).last;
    await tester.enterText(field, '그럼 술은?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    final history = requests.last['recent_history'] as List;
    expect(history.length, 2);
    expect(history.first['role'], 'user');
    expect(history.last['role'], 'assistant');
    expect(history.last['medicines'].single['product_name'], '선택약1정');
    expect(history.last.containsKey('sources'), isFalse);
    // Only the first, verified answer has a footer; the unverified reply has none.
    expect(find.text('출처: 식약처 의약품 허가정보'), findsOneWidget);
    await pick(tester, '선택약1정');
    await ask(tester);
    expect(requests.last['recent_history'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('건강 주의 답변은 조건과 위험 요인만 붉게 강조한다', (tester) async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return response({
          'reply': '선택약1정: 고혈압과 알코올, 술에 주의하세요. 수술은 별도 안내예요.',
          'resolved_intent': 'health_precautions',
          'health_highlight_terms': ['고혈압', '알코올', '술'],
        });
      }
      return response({
        'medicines': [
          for (final index in [1, 2, 3])
            {
              'medicine_code': '12345678$index',
              'product_name': '선택약$index정',
              'official_product_name': '선택약$index정',
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
    await pick(tester, '선택약1정');
    await tapCard(tester, '꼭 식사 후에 복용해야 하나요?');

    expect(sent, isNotNull);
    expect(sent!['user_id'], 'scope-user');
    expect(sent!['selected_medicine']['medicine_code'], '123456781');
    // 건강정보 자체는 앱이 실어 보내지 않는다. 서버가 아이디로 찾는다.
    expect(sent!.containsKey('health_profile'), isFalse);

    final answer = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.textSpan?.toPlainText() ==
                '선택약1정: 고혈압과 알코올, 술에 주의하세요. 수술은 별도 안내예요.',
      ),
    );
    final spans = (answer.textSpan! as TextSpan).children!
        .whereType<TextSpan>();
    final emphasized = spans
        .where(
          (span) =>
              span.style?.color == AppColors.danger &&
              span.style?.fontWeight == FontWeight.w700,
        )
        .map((span) => span.text);
    expect(emphasized, ['고혈압', '알코올', '술']);
    // 약 이름은 위험 요인이 아니다. 붉게 칠하지 않는다.
    expect(
      spans
          .where((span) => span.text?.contains('선택약1정') == true)
          .every((span) => span.style?.color != AppColors.danger),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('이름으로 찾은 약은 고른 뒤엔 하나로, 뺀 뒤엔 전체에 실린다', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('ai-subject-card')));
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
    // 약 하나를 고르면 그 약만 보낸다. 따로 적는 임시 목록은 없다.
    expect(sent.last.containsKey('temporary_medicines'), isFalse);

    await clearPick(tester);
    await ask(tester);
    // 고른 약이 없으면 이름으로 찾아 둔 약까지 모두 알콩이에게 넘긴다.
    expect(sent.last.containsKey('selected_medicine'), isFalse);
    expect(sent.last.containsKey('selected_medicines'), isFalse);
    expect(sent.last['temporary_medicines'][0]['medicine_code'], 'TEMP-1');
    expect(sent.last['user_id'], 'scope-user');

    await tester.tap(find.byKey(const ValueKey('ai-subject-card')));
    await tester.pumpAndSettle();
    // 등록한 약과 이름으로 찾은 약이 한 자리에 함께 선다. 출처 딱지는 없앴다.
    expect(find.text('어떤 약이 궁금하세요?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('medicine-selection-등록약정')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('medicine-selection-검색약정')),
      findsOneWidget,
    );
    expect(find.text('등록된 약'), findsNothing);
    expect(find.text('검색한 약'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
