import 'dart:async';
import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/features/drug_explain/drug_explain_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Widget appWith(http.Client client) {
    return MaterialApp(
      home: DrugExplainScreen(apiClient: ApiClient(client: client)),
    );
  }

  http.Response jsonResponse(Object body, {int statusCode = 200}) {
    return http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  testWidgets('두 글자와 400ms debounce 뒤에만 공식 후보를 검색한다', (tester) async {
    var searchCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [],
        });
      }
      searchCalls++;
      return jsonResponse({
        'query': request.url.queryParameters['q'],
        'count': 1,
        'items': [
          {'item_name': '게보린정', 'manufacturer': '삼진제약(주)', 'item_seq': '1'},
        ],
      });
    });

    await tester.pumpWidget(appWith(client));
    await tester.pump();
    await tester.tap(find.text('다른 약 검색하기'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('otherMedicineSearchField')),
      '게',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(searchCalls, 0);

    await tester.enterText(
      find.byKey(const Key('otherMedicineSearchField')),
      '게보',
    );
    await tester.pump(const Duration(milliseconds: 399));
    expect(searchCalls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(searchCalls, 1);
    expect(find.text('게보린정'), findsOneWidget);
    expect(find.text('삼진제약(주)'), findsOneWidget);
  });

  testWidgets('늦게 도착한 이전 검색 결과는 최신 결과를 덮지 않는다', (tester) async {
    final firstResponse = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [],
        });
      }
      if (request.url.queryParameters['q'] == '게보') {
        return firstResponse.future;
      }
      return jsonResponse({
        'query': '게보린',
        'count': 1,
        'items': [
          {'item_name': '게보린정', 'manufacturer': '삼진제약(주)', 'item_seq': '1'},
        ],
      });
    });

    await tester.pumpWidget(appWith(client));
    await tester.pump();
    await tester.tap(find.text('다른 약 검색하기'));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('otherMedicineSearchField'));

    await tester.enterText(field, '게보');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(field, '게보린');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('게보린정'), findsOneWidget);

    firstResponse.complete(
      jsonResponse({
        'query': '게보',
        'count': 1,
        'items': [
          {'item_name': '오래된검색결과', 'manufacturer': '이전제조사', 'item_seq': 'old'},
        ],
      }),
    );
    await tester.pump();
    expect(find.text('게보린정'), findsOneWidget);
    expect(find.text('오래된검색결과'), findsNothing);
  });

  testWidgets('사용자가 고른 공식 품목명이 선택되고 빠른 질문에 사용된다', (tester) async {
    final chatBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [],
        });
      }
      if (request.url.path.endsWith('/drug-explain/chat')) {
        chatBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return jsonResponse({'reply': '복용방법 답변'});
      }
      return jsonResponse({
        'query': '게보',
        'count': 2,
        'items': [
          {'item_name': '게보린정', 'manufacturer': '삼진제약(주)', 'item_seq': '1'},
          {'item_name': '게보린릴랙스연질캡슐', 'manufacturer': '다른제조사', 'item_seq': '2'},
        ],
      });
    });

    await tester.pumpWidget(appWith(client));
    await tester.pump();
    await tester.tap(find.text('다른 약 검색하기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('otherMedicineSearchField')),
      '게보',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('게보린정'));
    await tester.pumpAndSettle();

    final selectedMedicineChip = find.widgetWithText(ChoiceChip, '게보린정');
    expect(tester.widget<ChoiceChip>(selectedMedicineChip).selected, isTrue);
    await tester.tap(find.text('#복용방법'));
    await tester.pumpAndSettle();
    expect(chatBodies.last['message'], '게보린정의 복용방법을 공식 의약품 정보 기준으로 알려주세요.');
    expect(chatBodies.last['selected_medicine'], {
      'medicine_code': '1',
      'product_name': '게보린정',
    });

    await tester.tap(selectedMedicineChip);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(selectedMedicineChip).selected, isFalse);
    await tester.tap(selectedMedicineChip);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(selectedMedicineChip).selected, isTrue);
    await tester.tap(find.text('#복용방법'));
    await tester.pumpAndSettle();
    expect(chatBodies.last.containsKey('selected_medicine'), isFalse);
    expect(find.text('복용방법 답변'), findsOneWidget);
  });

  testWidgets('빠른 질문 8종은 선택 약으로 만든 기존 문장을 즉시 전송한다', (tester) async {
    final originalUserId = MvpSession.userId;
    MvpSession.userId = 'quick-question-test-user';
    addTearDown(() => MvpSession.userId = originalUserId);

    final sentMessages = <String>[];
    final sentIntents = <String>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [
            {'product_name': '게보린정'},
          ],
        });
      }
      if (request.url.path.endsWith('/drug-explain/chat')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('selected_medicine'), isFalse);
        sentMessages.add(body['message'] as String);
        sentIntents.add(body['intent'] as String);
        return jsonResponse({'reply': '빠른 질문 답변'});
      }
      throw StateError('unexpected request: ${request.url.path}');
    });
    const expected = <String, String>{
      '#약효·효능': '게보린정의 약효와 효능을 공식 의약품 정보 기준으로 알려주세요.',
      '#복용방법': '게보린정의 복용방법을 공식 의약품 정보 기준으로 알려주세요.',
      '#주의사항': '게보린정 복용 시 주의사항을 알려주세요.',
      '#부작용': '게보린정의 공식 부작용을 알려주세요.',
      '#같이 먹는 약': '게보린정과 현재 먹는 약들을 같이 복용해도 되는지 기존 DUR 병용금기 분석 결과를 설명해주세요.',
      '#나이별 주의': '게보린정의 나이별 주의사항을 기존 DUR 연령금기 분석 결과로 설명해주세요.',
      '#임신 중 주의': '게보린정의 임신 중 복용 주의사항을 기존 DUR 임부금기 분석 결과로 설명해주세요.',
      '#비슷한 약 중복':
          '게보린정과 현재 먹는 약에 비슷한 효능의 약이 중복되는지 기존 DUR 효능군중복 분석 결과로 설명해주세요.',
    };
    const expectedIntents = <String, String>{
      '#약효·효능': 'efficacy',
      '#복용방법': 'dosage',
      '#주의사항': 'precautions',
      '#부작용': 'side_effects',
      '#같이 먹는 약': 'combination',
      '#나이별 주의': 'age',
      '#임신 중 주의': 'pregnancy',
      '#비슷한 약 중복': 'duplicate',
    };

    for (final entry in expected.entries) {
      await tester.pumpWidget(appWith(client));
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, entry.key),
      );
      chip.onSelected!(true);
      await tester.pumpAndSettle();
      expect(sentMessages.last, entry.value);
      expect(sentIntents.last, expectedIntents[entry.key]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    expect(sentMessages, expected.values.toList());
    expect(sentIntents, expectedIntents.values.toList());
  });

  testWidgets('자유 질문 전송에는 explicit intent를 포함하지 않는다', (tester) async {
    Map<String, dynamic>? chatBody;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [],
        });
      }
      chatBody = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonResponse({'reply': '자유 질문 답변'});
    });

    await tester.pumpWidget(appWith(client));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '이 약은 식후에 먹나요?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(chatBody?['message'], '이 약은 식후에 먹나요?');
    expect(chatBody?.containsKey('intent'), isFalse);
  });

  testWidgets('서버 fallback 응답을 다른 약의 데모 답변으로 바꾸지 않는다', (tester) async {
    const serverReply = '현재 AI 약사가 설정되지 않아 공식 답변을 생성할 수 없습니다.';
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [],
        });
      }
      return jsonResponse({'reply': serverReply});
    });

    await tester.pumpWidget(appWith(client));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '게보린정의 효능을 알려주세요.');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text(serverReply), findsOneWidget);
    expect(find.textContaining('타이레놀정의 주요 효능'), findsNothing);
  });

  testWidgets('검색 약과 기존 복용약의 payload 출처를 구분한다', (tester) async {
    final chatBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [
            {'product_name': '기존약A'},
          ],
        });
      }
      if (request.url.path.endsWith('/drug-explain/chat')) {
        chatBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return jsonResponse({'reply': '답변'});
      }
      final query = request.url.queryParameters['q'];
      return jsonResponse({
        'query': query,
        'count': 1,
        'items': [
          {
            'item_name': query == '검색D' ? '검색약D' : '검색약C',
            'manufacturer': '제조사',
            'item_seq': query == '검색D' ? '4' : '3',
          },
        ],
      });
    });

    await tester.pumpWidget(appWith(client));
    await tester.pumpAndSettle();

    Future<void> selectSearchResult(String query, String result) async {
      await tester.tap(find.text('다른 약 검색하기'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('otherMedicineSearchField')),
        query,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.text(result));
      await tester.pumpAndSettle();
    }

    await selectSearchResult('검색C', '검색약C');
    await tester.tap(find.text('기존약A'));
    await tester.pump();
    await tester.tap(find.text('#복용방법'));
    await tester.pumpAndSettle();
    expect(chatBodies.last.containsKey('selected_medicine'), isFalse);

    await selectSearchResult('검색D', '검색약D');
    await tester.tap(find.text('#복용방법'));
    await tester.pumpAndSettle();
    expect(chatBodies.last['selected_medicine'], {
      'medicine_code': '4',
      'product_name': '검색약D',
    });

    await tester.tap(find.text('다른 약 검색하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#복용방법'));
    await tester.pumpAndSettle();
    expect(chatBodies.last['selected_medicine'], {
      'medicine_code': '4',
      'product_name': '검색약D',
    });
  });

  testWidgets('약 미선택 시 빠른 질문은 API를 호출하지 않고 안내한다', (tester) async {
    var chatCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [],
        });
      }
      chatCalls++;
      return jsonResponse({'reply': '호출되면 안 됨'});
    });

    await tester.pumpWidget(appWith(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#약효·효능'));
    await tester.pump();

    expect(chatCalls, 0);
    expect(find.text('먼저 궁금한 약을 선택해주세요.'), findsOneWidget);
  });

  testWidgets('약 Chip은 재탭 해제와 다른 약으로 단일 선택 전환이 가능하다', (tester) async {
    final originalUserId = MvpSession.userId;
    MvpSession.userId = 'medicine-toggle-test-user';
    addTearDown(() => MvpSession.userId = originalUserId);

    var chatCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [
            {'product_name': '게보린정'},
            {'product_name': '알마겔정'},
          ],
        });
      }
      chatCalls++;
      return jsonResponse({'reply': '효능 답변'});
    });

    await tester.pumpWidget(appWith(client));
    await tester.pumpAndSettle();
    final geborin = find.widgetWithText(ChoiceChip, '게보린정');
    final almagel = find.widgetWithText(ChoiceChip, '알마겔정');

    expect(tester.widget<ChoiceChip>(geborin).selected, isFalse);
    expect(tester.widget<ChoiceChip>(almagel).selected, isFalse);

    await tester.tap(geborin);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(geborin).selected, isTrue);

    await tester.tap(geborin);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(geborin).selected, isFalse);

    await tester.tap(geborin);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(geborin).selected, isTrue);

    await tester.tap(almagel);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(geborin).selected, isFalse);
    expect(tester.widget<ChoiceChip>(almagel).selected, isTrue);

    await tester.tap(almagel);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(almagel).selected, isFalse);

    await tester.tap(find.text('#약효·효능'));
    await tester.pump();
    expect(chatCalls, 0);
    expect(find.text('먼저 궁금한 약을 선택해주세요.'), findsOneWidget);

    await tester.tap(geborin);
    await tester.pump();
    await tester.tap(find.text('#약효·효능'));
    await tester.pumpAndSettle();
    expect(chatCalls, 1);
    expect(find.text('효능 답변'), findsOneWidget);
  });

  testWidgets('빠른 질문 로딩 중 중복 요청을 막고 자유 질문 전송은 유지한다', (tester) async {
    final originalUserId = MvpSession.userId;
    MvpSession.userId = 'quick-question-test-user';
    addTearDown(() => MvpSession.userId = originalUserId);

    final firstReply = Completer<http.Response>();
    final sentMessages = <String>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [
            {'product_name': '게보린정'},
          ],
        });
      }
      sentMessages.add(
        (jsonDecode(request.body) as Map<String, dynamic>)['message'] as String,
      );
      if (sentMessages.length == 1) return firstReply.future;
      return jsonResponse({'reply': '자유 질문 답변'});
    });

    await tester.pumpWidget(appWith(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#부작용'));
    await tester.pump();
    await tester.tap(find.text('#복용방법'), warnIfMissed: false);
    await tester.pump();
    expect(sentMessages, ['게보린정의 공식 부작용을 알려주세요.']);

    firstReply.complete(jsonResponse({'reply': '부작용 답변'}));
    await tester.pumpAndSettle();
    final chatField = find.byType(TextField);
    await tester.enterText(chatField, '이 약은 식후에 먹어도 되나요?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(sentMessages.last, '이 약은 식후에 먹어도 되나요?');
    expect(find.text('자유 질문 답변'), findsOneWidget);
  });

  testWidgets('검색 결과 없음과 네트워크 오류를 안전한 문구로 표시한다', (tester) async {
    var failSearch = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [],
        });
      }
      if (failSearch) throw http.ClientException('private network detail');
      return jsonResponse({'query': '없음', 'count': 0, 'items': []});
    });

    await tester.pumpWidget(appWith(client));
    await tester.pump();
    await tester.tap(find.text('다른 약 검색하기'));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('otherMedicineSearchField'));

    await tester.enterText(field, '없음');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('검색된 공식 의약품이 없습니다.'), findsOneWidget);

    failSearch = true;
    await tester.enterText(field, '오류');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('네트워크 연결을 확인한 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.textContaining('private network detail'), findsNothing);
  });
}
