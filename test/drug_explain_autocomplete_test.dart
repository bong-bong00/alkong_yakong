import 'dart:async';
import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
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
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/dashboard')) {
        return jsonResponse({
          'latest_prescription': null,
          'today_medications': [],
        });
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

    await tester.tap(find.text('#복용방법'));
    await tester.pump();
    final chatField = tester.widget<TextField>(find.byType(TextField));
    expect(chatField.controller!.text, '게보린정의 복용방법을 공식 의약품 정보 기준으로 알려주세요.');
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
