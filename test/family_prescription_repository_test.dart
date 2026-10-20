import 'dart:convert';

import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/features/prescription/data/family_prescription_repository.dart';
import 'package:alkong_yakong/features/prescription/data/prescription_help_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'same prescription ID with a new registration revision is detected',
    () async {
      var revision = 'first';
      final api = ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {'id': 'same', 'registration_revision': revision, 'items': []},
            ]),
            200,
          ),
        ),
      );
      final repo = FamilyPrescriptionRepository(apiClient: api);
      await repo.begin('patient');
      expect(await repo.arrivals('patient'), isEmpty);
      revision = 'again';
      expect((await repo.arrivals('patient')).single['id'], 'same');
    },
  );

  Map<String, dynamic> prescription(String id) => {
    'id': id,
    'items': [
      {'medicine_code': 'same-code', 'product_name': '아디팜정'},
    ],
  };

  test(
    'same medicine in a new prescription is detected after restart',
    () async {
      var records = [prescription('old')];
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/users/patient/prescriptions');
          return http.Response(
            jsonEncode(records),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await FamilyPrescriptionRepository(apiClient: api).begin('patient');
      records = [prescription('new'), prescription('old')];
      final restored = FamilyPrescriptionRepository(apiClient: api);
      expect(await restored.isPending('patient'), isTrue);
      expect((await restored.arrivals('patient')).single['id'], 'new');
      await restored.finish('patient');
      expect(await restored.isPending('patient'), isFalse);
    },
  );

  test('first empty account detects its first registration', () async {
    var records = <Map<String, dynamic>>[];
    final repo = FamilyPrescriptionRepository(
      apiClient: ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(records),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );
    await repo.begin('patient');
    expect(await repo.arrivals('patient'), isEmpty);
    records = [prescription('first')];
    expect((await repo.arrivals('patient')).single['id'], 'first');
  });

  test('old records are not arrivals; accounts stay separate', () async {
    final repo = FamilyPrescriptionRepository(
      apiClient: ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([prescription('old')]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );
    await repo.begin('patient');
    expect(await repo.arrivals('patient'), isEmpty);
    expect(await repo.isPending('another-patient'), isFalse);
    await expectLater(
      repo.arrivals('another-patient'),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'query failure is not an empty result and keeps pending request',
    () async {
      var status = 200;
      final repo = FamilyPrescriptionRepository(
        apiClient: ApiClient(
          client: MockClient((_) async => http.Response('[]', status)),
        ),
      );
      await repo.begin('patient');
      status = 503;
      await expectLater(repo.arrivals('patient'), throwsA(isA<ApiException>()));
      expect(await repo.isPending('patient'), isTrue);
    },
  );

  test('snapshot is captured before sending help request', () async {
    final calls = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        calls.add(request.method);
        return http.Response(
          request.method == 'GET' ? '[]' : '{"sent":true}',
          200,
        );
      }),
    );
    final result = await PrescriptionHelpRepository(
      apiClient: api,
      registrations: FamilyPrescriptionRepository(apiClient: api),
    ).ask('patient');
    expect(result.isSent, isTrue);
    expect(calls, ['GET', 'POST']);
  });

  test(
    'failed baseline query does not send a misleading help request',
    () async {
      final calls = <String>[];
      final api = ApiClient(
        client: MockClient((request) async {
          calls.add(request.method);
          return http.Response('{}', 503);
        }),
      );
      final registrations = FamilyPrescriptionRepository(apiClient: api);
      final result = await PrescriptionHelpRepository(
        apiClient: api,
        registrations: registrations,
      ).ask('patient');
      expect(result.outcome, PrescriptionHelpOutcome.failed);
      expect(calls, ['GET']);
      expect(await registrations.isPending('patient'), isFalse);
    },
  );

  test(
    'malformed prescription response is an error, not an empty list',
    () async {
      final repo = FamilyPrescriptionRepository(
        apiClient: ApiClient(
          client: MockClient((_) async => http.Response('{"items":[]}', 200)),
        ),
      );
      await expectLater(repo.begin('patient'), throwsA(isA<ApiException>()));
      expect(await repo.isPending('patient'), isFalse);
    },
  );

  test('no linked guardian clears the pending request', () async {
    final api = ApiClient(
      client: MockClient(
        (request) async => http.Response(
          request.method == 'GET' ? '[]' : '{"sent":false}',
          200,
        ),
      ),
    );
    final registrations = FamilyPrescriptionRepository(apiClient: api);
    final result = await PrescriptionHelpRepository(
      apiClient: api,
      registrations: registrations,
    ).ask('patient');
    expect(result.outcome, PrescriptionHelpOutcome.noGuardian);
    expect(await registrations.isPending('patient'), isFalse);
  });
}
