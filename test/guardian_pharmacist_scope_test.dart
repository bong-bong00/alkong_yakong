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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alkong_yakong/features/guardian/presentation/screens/guardian_pharmacist_screen.dart';
import 'package:alkong_yakong/features/guardian/application/guardians_provider.dart';
import 'package:alkong_yakong/features/dashboard/presentation/screens/patient_data.dart';

void main() {
  http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MvpSession.userId = 'guardian';
    MvpSession.latestOcrItems = [
      {'official_product_name': '보호자본인약정', 'medicine_code': '111111111'},
    ];
  });

  for (final scale in [1.0, 2.0]) {
    for (final subject in [null, 'patient-a']) {
      testWidgets(
        'guardian $subject selector fits small phone at scale $scale',
        (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final client = MockClient(
            (request) async => request.url.path.endsWith('/cache-context')
                ? jsonResponse({'verified': true, 'fingerprint': 'v1'})
                : jsonResponse({'medicines': []}),
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                careOverviewProvider.overrideWith(
                  (ref) async => const CareOverview(
                    patients: [
                      CarePatient(
                        linkId: 'link',
                        patientId: 'patient-a',
                        name: '긴 이름의 시연 사용자',
                        relation: '아버지',
                      ),
                    ],
                  ),
                ),
              ],
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: GuardianPharmacistScreen(
                  initialPatientId: subject,
                  apiClient: ApiClient(client: client),
                  medicationApiClient: ApiClient(client: client),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('guardian selector separates general and patient consultation', (
    tester,
  ) async {
    final requests = <Map>[];
    final reads = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map;
        requests.add(body);
        return jsonResponse({
          'reply': '${body['consultation_mode'] ?? body['user_id']} 답변이에요.',
          'sources': [],
        });
      }
      reads.add(request.url.toString());
      return request.url.path.endsWith('/cache-context')
          ? jsonResponse({'verified': true, 'fingerprint': 'patient-v1'})
          : jsonResponse({'medicines': []});
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          careOverviewProvider.overrideWith(
            (ref) async => const CareOverview(
              patients: [
                CarePatient(
                  linkId: 'link',
                  patientId: 'patient-a',
                  name: '김환자',
                  relation: '아버지',
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          home: GuardianPharmacistScreen(
            apiClient: ApiClient(client: client),
            medicationApiClient: ApiClient(client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, isEmpty);
    expect(find.textContaining('보호자본인약정'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '약 보관법은요?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(requests.last['consultation_mode'], 'general');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('김환자 님 약 상담').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('general 답변', findRichText: true), findsNothing);
    await tester.enterText(find.byType(TextField).last, '주의할 점은요?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(requests.last['user_id'], 'patient-a');
    expect(requests.last['consultation_mode'], 'patient_all');
    expect(find.text('약 고르기'), findsNothing);
    expect(MvpSession.userId, 'guardian');
    expect(
      await PharmacistConversationStore().load('guardian::general'),
      hasLength(1),
    );
    expect(
      await PharmacistConversationStore().load('guardian::patient::patient-a'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'guardian self and each patient have separate requests and saved histories',
    (tester) async {
      final posted = <String>[];
      final reads = <String>[];
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map;
          posted.add(body['user_id'] as String);
          return jsonResponse({
            'reply': '${body['user_id']} 전용답변이에요.',
            'sources': ['식약처 의약품 허가정보'],
          });
        }
        reads.add(request.url.toString());
        if (request.url.path.endsWith('/cache-context')) {
          return jsonResponse({
            'verified': true,
            'fingerprint': request.url.queryParameters['user_id'],
          });
        }
        return jsonResponse({'medicines': []});
      });
      for (final subject in ['patient-a', 'patient-b', 'guardian']) {
        await tester.pumpWidget(
          MaterialApp(
            home: DrugExplainScreen(
              key: ValueKey(subject),
              patientId: subject == 'guardian' ? null : subject,
              patientName: subject == 'guardian' ? null : subject,
              apiClient: ApiClient(client: client),
              medicationApiClient: ApiClient(client: client),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (subject != 'guardian') {
          expect(
            find.byKey(const ValueKey('guardian-chat-subject')),
            findsOneWidget,
          );
        }
        await tester.enterText(find.byType(TextField).last, '내 건강에서 주의할 점은요?');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();
        expect(posted.last, subject);
        expect(MvpSession.userId, 'guardian');
      }
      final store = PharmacistConversationStore();
      for (final subject in ['patient-a', 'patient-b', 'guardian']) {
        final key = subject == 'guardian'
            ? 'guardian'
            : 'guardian::patient::$subject';
        final saved = await store.load(key);
        expect(saved, hasLength(1));
        final messages = saved.single['messages'] as List;
        expect(messages.any((m) => m['text'] == '$subject 전용답변이에요.'), isTrue);
      }
      expect(reads.any((p) => p.contains('/patient-a/medicines')), isTrue);
      expect(reads.any((p) => p.contains('/patient-b/medicines')), isTrue);
      expect(reads.any((p) => p.contains('user_id=patient-a')), isTrue);
    },
  );

  testWidgets(
    'revoked guardian cannot show previous patient history or reuse answers',
    (tester) async {
      var revoked = false;
      var posts = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/cache-context')) {
          return revoked
              ? jsonResponse({'detail': '연결 해제'}, 403)
              : jsonResponse({'verified': true, 'fingerprint': 'v1'});
        }
        if (request.method == 'POST') {
          posts++;
          return jsonResponse({
            'reply': '환자만의 답변이에요.',
            'sources': ['식약처 의약품 허가정보'],
          });
        }
        return jsonResponse({'medicines': []});
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DrugExplainScreen(
            patientId: 'patient-a',
            patientName: '환자A',
            apiClient: ApiClient(client: client),
            medicationApiClient: ApiClient(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '주의할 점은요?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(posts, 1);
      revoked = true;
      await tester.tap(find.text('이전 대화'));
      await tester.pumpAndSettle();
      expect(find.textContaining('환자만의 답변', findRichText: true), findsNothing);
      await tester.enterText(find.byType(TextField).last, '주의할 점은요?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(MvpSession.userId, 'guardian');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account switch cannot send from an already open patient screen',
    (tester) async {
      var posts = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') posts++;
        return request.url.path.endsWith('/cache-context')
            ? jsonResponse({'verified': true, 'fingerprint': 'v1'})
            : jsonResponse({'medicines': []});
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DrugExplainScreen(
            patientId: 'patient-a',
            patientName: '환자A',
            apiClient: ApiClient(client: client),
            medicationApiClient: ApiClient(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      MvpSession.userId = 'another-guardian';
      await tester.enterText(find.byType(TextField).last, '주의할 점은요?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(posts, 0);
      expect(find.textContaining('로그인 계정이 바뀌었어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account change during permission verification blocks sending', (
    tester,
  ) async {
    var switchDuringCheck = false;
    var posts = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') posts++;
      if (request.url.path.endsWith('/cache-context')) {
        if (switchDuringCheck) MvpSession.userId = 'another-guardian';
        return jsonResponse({'verified': true, 'fingerprint': 'v1'});
      }
      return jsonResponse({'medicines': []});
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DrugExplainScreen(
          patientId: 'patient-a',
          patientName: '환자A',
          apiClient: ApiClient(client: client),
          medicationApiClient: ApiClient(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    switchDuringCheck = true;
    await tester.enterText(find.byType(TextField).last, '주의할 점은요?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(posts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('patient context never falls back to guardians last OCR', (
    tester,
  ) async {
    final client = MockClient(
      (request) async => request.url.path.endsWith('/cache-context')
          ? jsonResponse({'verified': true, 'fingerprint': 'v1'})
          : jsonResponse({'detail': 'unavailable'}, 503),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DrugExplainScreen(
          patientId: 'patient-a',
          patientName: '환자A',
          apiClient: ApiClient(client: client),
          medicationApiClient: ApiClient(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('보호자본인약정'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
