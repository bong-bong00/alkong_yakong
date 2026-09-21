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

  // 물어볼 약은 이제 "바꾸기"로 여는 창에서 고른다.
  Future<void> openSubjectDialog(WidgetTester tester) async {
    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();
  }

  // 창에서는 약을 굴려서 가운데로 놓고, "이 약으로 정하기"를 누른다.
  // 굴림판은 세 칸만 그리므로 맨 위로 되돌린 뒤 한 칸씩 굴려 찾는다.
  Future<void> pickSubject(WidgetTester tester, String label) async {
    await openSubjectDialog(tester);
    final wheel = find.byType(ListWheelScrollView);
    await tester.drag(wheel, const Offset(0, 600));
    await tester.pumpAndSettle();
    final option = find.descendant(of: wheel, matching: find.text(label));
    for (var i = 0; i < 20 && option.evaluate().isEmpty; i++) {
      await tester.drag(wheel, const Offset(0, -66));
      await tester.pumpAndSettle();
    }
    await tester.tap(option);
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 약으로 정하기'));
    await tester.pumpAndSettle();
  }

  Future<void> openOtherMedicineSearch(WidgetTester tester) async {
    await openSubjectDialog(tester);
    await tester.tap(find.text('다른 약 검색하기'));
    await tester.pumpAndSettle();
  }

  testWidgets('두 글자와 550ms debounce 뒤에만 공식 후보를 검색한다', (tester) async {
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
    await openOtherMedicineSearch(tester);

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
    await tester.pump(const Duration(milliseconds: 549));
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
    await openOtherMedicineSearch(tester);
    final field = find.byKey(const Key('otherMedicineSearchField'));

    await tester.enterText(field, '게보');
    await tester.pump(const Duration(milliseconds: 550));
    await tester.enterText(field, '게보린');
    await tester.pump(const Duration(milliseconds: 550));
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
    await openOtherMedicineSearch(tester);
    await tester.enterText(
      find.byKey(const Key('otherMedicineSearchField')),
      '게보',
    );
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await tester.tap(find.text('게보린정'));
    await tester.pumpAndSettle();

    expect(find.text('게보린정'), findsOneWidget);
    await tester.tap(find.text('어떻게 먹나요?'));
    await tester.pumpAndSettle();
    expect(
      chatBodies.last['message'],
      '이 약은 보통 어떻게 먹나요? 제가 등록한 복용 방법과 제품의 일반적인 사용법을 구분해서 알려주세요.',
    );
    expect(chatBodies.last['selected_medicine'], {
      'medicine_code': '1',
      'product_name': '게보린정',
    });

    // "약 전체"로 돌렸다가 다시 고르면 공식 품목 코드도 함께 돌아온다.
    await pickSubject(tester, '약 전체');
    expect(find.text('어떻게 먹나요?'), findsNothing);
    await pickSubject(tester, '게보린정');
    await tester.tap(find.text('어떻게 먹나요?'));
    await tester.pumpAndSettle();
    expect(chatBodies.last['selected_medicine'], {
      'medicine_code': '1',
      'product_name': '게보린정',
    });
    expect(find.text('복용방법 답변'), findsNWidgets(2));
  });

  testWidgets('공식 code가 있는 저장 약 chip은 selected_medicine을 전송한다', (tester) async {
    Map<String, dynamic>? chatBody;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [
            {'medicine_code': '197900145', 'product_name': '유한메토트렉세이트정'},
          ],
        });
      }
      if (request.url.path.endsWith('/drug-explain/chat')) {
        chatBody = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({'reply': '공식정보 답변'});
      }
      throw StateError('unexpected request: ${request.url.path}');
    });

    await tester.pumpWidget(appWith(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('어디에 쓰는 약인가요?'));
    await tester.pumpAndSettle();

    expect(chatBody?['selected_medicine'], {
      'medicine_code': '197900145',
      'product_name': '유한메토트렉세이트정',
    });
  });

  testWidgets('빠른 질문 7종은 쉬운 문장과 기존 intent를 전송한다', (tester) async {
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
      '어디에 쓰는 약인가요?': '이 약은 어디에 쓰는 약인가요?',
      '어떻게 먹나요?': '이 약은 보통 어떻게 먹나요? 제가 등록한 복용 방법과 제품의 일반적인 사용법을 구분해서 알려주세요.',
      '무엇을 조심해야 하나요?': '이 약을 먹을 때 무엇을 조심해야 하나요?',
      '먹고 불편하면 어떻게 하나요?': '이 약을 먹고 불편한 증상이 생기면 어떻게 해야 하나요?',
      '다른 약과 같이 먹기':
          '이 약을 제가 먹고 있는 약들과 같이 먹어도 되는지 확인해 주세요. 같은 성분이나 비슷한 역할의 약이 겹치는지도 알려주세요.',
      '나이에 따라 조심할 점': '제 나이에 이 약을 사용할 때 조심할 점이 있나요?',
      '임신 중에 조심할 점': '임신 중에 이 약을 사용할 때 조심할 점이 있나요?',
    };
    const expectedIntents = <String, String>{
      '어디에 쓰는 약인가요?': 'efficacy',
      '어떻게 먹나요?': 'dosage',
      '무엇을 조심해야 하나요?': 'precautions',
      '먹고 불편하면 어떻게 하나요?': 'side_effects',
      '다른 약과 같이 먹기': 'combination',
      '나이에 따라 조심할 점': 'age',
      '임신 중에 조심할 점': 'pregnancy',
    };

    for (final entry in expected.entries) {
      await tester.pumpWidget(appWith(client));
      await tester.pumpAndSettle();
      expect(find.text('게보린정'), findsOneWidget);
      final keywordChip = find.widgetWithText(ChoiceChip, entry.key);
      await tester.ensureVisible(keywordChip);
      await tester.tap(keywordChip);
      await tester.pumpAndSettle();
      expect(sentMessages.last, entry.value);
      expect(sentIntents.last, expectedIntents[entry.key]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    expect(sentMessages, expected.values.toList());
    expect(sentIntents, expectedIntents.values.toList());
  });

  testWidgets('통합 질문은 공식 품목 identity와 combination을 한 번만 보낸다', (tester) async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [
            {'medicine_code': '197900145', 'product_name': '유한메토트렉세이트정'},
          ],
        });
      }
      if (request.url.path.endsWith('/drug-explain/chat')) {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return jsonResponse({'reply': '확인한 공식 내용을 설명해 드릴게요.'});
      }
      throw StateError('unexpected request: ${request.url.path}');
    });

    await tester.pumpWidget(appWith(client));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '다른 약과 같이 먹기'), findsOneWidget);
    expect(find.text('같이 먹는 약'), findsNothing);
    expect(find.text('비슷한 약 중복'), findsNothing);
    expect(find.textContaining('#'), findsNothing);

    final button = find.widgetWithText(ChoiceChip, '다른 약과 같이 먹기');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single['intent'], 'combination');
    expect(requests.single['selected_medicine'], {
      'medicine_code': '197900145',
      'product_name': '유한메토트렉세이트정',
    });
    expect(
      requests.single['message'],
      '이 약을 제가 먹고 있는 약들과 같이 먹어도 되는지 확인해 주세요. 같은 성분이나 비슷한 역할의 약이 겹치는지도 알려주세요.',
    );
    expect(find.text('다른 약과 함께 쓸 때 조심하거나 겹치는 약이 있나요?'), findsOneWidget);
    for (final term in ['DUR', '병용금기', '효능군중복', '중복성분']) {
      expect(find.textContaining(term), findsNothing);
    }
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('좁은 ${width.toInt()}px 화면에서도 빠른 질문과 마지막 답변에 접근한다', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/dashboard')) {
          return jsonResponse({
            'latest_prescription': null,
            'today_medications': [
              {'medicine_code': '197900145', 'product_name': '유한메토트렉세이트정'},
            ],
          });
        }
        if (request.url.path.endsWith('/drug-explain/chat')) {
          return jsonResponse({'reply': '공식 자료에서 확인한 내용을 알려드릴게요.'});
        }
        throw StateError('unexpected request: ${request.url.path}');
      });

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: appWith(client),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final first = find.widgetWithText(ChoiceChip, '어디에 쓰는 약인가요?');
      expect(tester.getTopLeft(first).dx, greaterThanOrEqualTo(0));
      final last = find.widgetWithText(ChoiceChip, '임신 중에 조심할 점');
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(last).dx, lessThanOrEqualTo(width));
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final reply = find.text('공식 자료에서 확인한 내용을 알려드릴게요.');
      await tester.ensureVisible(reply);
      await tester.pumpAndSettle();
      final inputTop = tester.getTopLeft(find.byType(TextField).first).dy;
      expect(tester.getBottomRight(reply).dy, lessThan(inputTop));

      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.showKeyboard(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomRight(reply).dy,
        lessThan(tester.getTopLeft(find.byType(TextField).first).dy),
      );
    });
  }

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
      await openOtherMedicineSearch(tester);
      await tester.enterText(
        find.byKey(const Key('otherMedicineSearchField')),
        query,
      );
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await tester.tap(find.text(result));
      await tester.pumpAndSettle();
    }

    await selectSearchResult('검색C', '검색약C');
    await pickSubject(tester, '기존약A');
    await tester.tap(find.text('어떻게 먹나요?'));
    await tester.pumpAndSettle();
    expect(chatBodies.last.containsKey('selected_medicine'), isFalse);

    await selectSearchResult('검색D', '검색약D');
    await tester.tap(find.text('어떻게 먹나요?'));
    await tester.pumpAndSettle();
    expect(chatBodies.last['selected_medicine'], {
      'medicine_code': '4',
      'product_name': '검색약D',
    });

    await openOtherMedicineSearch(tester);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('어떻게 먹나요?'));
    await tester.pumpAndSettle();
    expect(chatBodies.last['selected_medicine'], {
      'medicine_code': '4',
      'product_name': '검색약D',
    });
  });

  testWidgets('약을 안 골랐으면 빠른 질문을 아예 내놓지 않는다', (tester) async {
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

    expect(find.text('약 전체'), findsOneWidget);
    expect(find.text('어디에 쓰는 약인가요?'), findsNothing);
    expect(chatCalls, 0);
    // 대신 바로 누를 수 있는 예시 질문이 있다.
    expect(find.text('이 약은 무슨 약이에요?'), findsOneWidget);
  });

  testWidgets('창에서 고른 약 하나만 물어볼 약이 된다', (tester) async {
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

    // 약이 둘이면 무엇을 물을지 먼저 고르게 한다.
    expect(find.text('약 전체'), findsOneWidget);
    expect(find.text('어디에 쓰는 약인가요?'), findsNothing);

    await pickSubject(tester, '게보린정');
    expect(find.text('게보린정'), findsOneWidget);

    await pickSubject(tester, '알마겔정');
    expect(find.text('알마겔정'), findsOneWidget);
    expect(find.text('게보린정'), findsNothing);

    await pickSubject(tester, '약 전체');
    expect(find.text('어디에 쓰는 약인가요?'), findsNothing);
    expect(chatCalls, 0);

    await pickSubject(tester, '게보린정');
    await tester.tap(find.text('어디에 쓰는 약인가요?'));
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
    await tester.ensureVisible(
      find.widgetWithText(ChoiceChip, '먹고 불편하면 어떻게 하나요?'),
    );
    await tester.tap(find.text('먹고 불편하면 어떻게 하나요?'));
    await tester.pump();
    await tester.tap(find.text('어떻게 먹나요?'), warnIfMissed: false);
    await tester.pump();
    expect(sentMessages, ['이 약을 먹고 불편한 증상이 생기면 어떻게 해야 하나요?']);

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
    await openOtherMedicineSearch(tester);
    final field = find.byKey(const Key('otherMedicineSearchField'));

    await tester.enterText(field, '없음');
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(find.text('검색된 공식 의약품이 없습니다.'), findsOneWidget);

    failSearch = true;
    await tester.enterText(field, '오류');
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(find.text('네트워크 연결을 확인한 후 다시 시도해주세요.'), findsOneWidget);
    expect(find.textContaining('private network detail'), findsNothing);
  });

  testWidgets('동일 검색어의 진행 중 요청과 직전 성공 요청을 중복 전송하지 않는다', (tester) async {
    var searchCalls = 0;
    final pending = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [],
        });
      }
      searchCalls++;
      return pending.future;
    });

    await tester.pumpWidget(appWith(client));
    await tester.pump();
    await openOtherMedicineSearch(tester);
    final field = find.byKey(const Key('otherMedicineSearchField'));

    await tester.enterText(field, '게보');
    await tester.pump(const Duration(milliseconds: 550));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(searchCalls, 1);

    pending.complete(
      jsonResponse({
        'query': '게보',
        'count': 1,
        'items': [
          {'item_name': '게보린정', 'manufacturer': '삼진제약', 'item_seq': '1'},
        ],
      }),
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(searchCalls, 1);
  });

  testWidgets('검색 실패 후에는 같은 검색어를 다시 요청할 수 있다', (tester) async {
    var searchCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [],
        });
      }
      searchCalls++;
      if (searchCalls == 1) throw http.ClientException('temporary failure');
      return jsonResponse({
        'query': '게보',
        'count': 1,
        'items': [
          {'item_name': '게보린정', 'manufacturer': '삼진제약', 'item_seq': '1'},
        ],
      });
    });

    await tester.pumpWidget(appWith(client));
    await tester.pump();
    await openOtherMedicineSearch(tester);
    final field = find.byKey(const Key('otherMedicineSearchField'));

    await tester.enterText(field, '게보');
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(searchCalls, 1);
    expect(find.text('네트워크 연결을 확인한 후 다시 시도해주세요.'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(searchCalls, 2);
    expect(find.text('게보린정'), findsOneWidget);
  });
}
