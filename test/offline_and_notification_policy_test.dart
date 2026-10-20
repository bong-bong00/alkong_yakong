import 'dart:convert';
import 'support/authenticated_session.dart';
import 'package:alkong_yakong/core/network/api_client.dart';
import 'package:alkong_yakong/core/session/mvp_session.dart';
import 'package:alkong_yakong/core/session/session_credentials.dart';
import 'package:alkong_yakong/core/session/offline_status.dart';
import 'package:alkong_yakong/features/profile/data/user_repository.dart';
import 'package:alkong_yakong/features/guardian/application/guardian_alert_preferences.dart';
import 'package:alkong_yakong/features/guardian/data/alert_repository.dart';
import 'package:alkong_yakong/features/reminder/application/alarm_preferences.dart';
import 'package:alkong_yakong/features/reminder/application/reminder_notifications.dart';
import 'package:alkong_yakong/features/medication/domain/medication_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await SessionCredentials.install(loginResponse('patient'));
    MvpSession.userId = 'patient';
    OfflineStatus.clear();
  });

  test(
    'cached own profile works offline but never after 401 clears credentials',
    () async {
      var status = 200;
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], startsWith('Bearer '));
          return http.Response(
            jsonEncode({
              'id': 'patient',
              'name': '테스트',
              'phone': '01000000000',
              'role': 'PATIENT',
            }),
            status,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final repo = UserRepository(apiClient: api);
      await repo.fetch('patient');
      status = 503;
      expect((await repo.fetch('patient')).id, 'patient');
      expect(OfflineStatus.active.value, isTrue);
      status = 401;
      await expectLater(repo.fetch('patient'), throwsA(isA<ApiException>()));
      status = 503;
      await expectLater(repo.fetch('patient'), throwsA(isA<ApiException>()));
    },
  );

  test(
    'medicine cache is only for own valid session; never caches writes or other patients',
    () async {
      var status = 200;
      final api = ApiClient(
        client: MockClient(
          (_) async => http.Response('{"medicines":[]}', status),
        ),
      );
      const own = '/api/v1/users/patient/medicines';
      await api.get(own);
      await api.get('/api/v1/users/other/medicines');
      status = 503;
      expect(await api.get(own), {'medicines': []});
      await expectLater(
        api.get('/api/v1/users/other/medicines'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.post('/api/v1/medication-logs/batch', body: {}),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'guardian preferences filter actual in-app alerts and stay account-scoped',
    () async {
      MvpSession.userId = 'guardian';
      SharedPreferences.setMockInitialValues({
        'guardian_alert_heart_guardian': false,
      });
      final repo = AlertRepository(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode([
                {'notification_type': 'HEART_RANGE_NOTICE'},
                {'notification_type': 'MEDICATION_MISSED'},
                {'notification_type': 'PRESCRIPTION_HELP_REQUEST'},
              ]),
              200,
            ),
          ),
        ),
      );
      expect((await repo.fetch('patient'))!.map((a) => a.type), [
        'miss',
        'help',
      ]);
      MvpSession.userId = 'another-guardian';
      expect((await repo.fetch('patient'))!.length, 3);
      expect(
        GuardianAlertPreferences.defaults.containsKey('guardian_alert_sms'),
        isFalse,
      );
    },
  );

  test(
    'a follow-up crossing slot boundary retains original medication slot',
    () {
      final reminders = ReminderPlan.forPrefs(
        const AlarmPreferences(times: [10 * 60 + 55]),
      );
      expect(reminders.first.slot, DoseSlot.morning);
      expect(reminders.last.hour, 11);
      expect(reminders.last.slot, DoseSlot.morning);
    },
  );
}
