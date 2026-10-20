import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../dashboard/presentation/screens/patient_data.dart';
import '../data/alert_repository.dart';
import 'guardians_provider.dart';

/// Acknowledgement belongs to the viewing guardian, not the patient's dose log.
class GuardianAlertInbox {
  Future<void> _writes = Future.value();
  final String ownerId;
  GuardianAlertInbox(this.ownerId);
  static int identity(AlertItem alert) {
    if (alert.id != null) return alert.id!;
    var hash = 17;
    for (final c
        in '${alert.type}|${alert.title}|${alert.desc}|${alert.time}'
            .codeUnits) {
      hash = (hash * 31 + c) & 0x3fffffff;
    }
    return -hash - 1;
  }

  String key(String patientId) => 'guardian_ack_${ownerId}_$patientId';
  Future<Set<int>> read(String patientId) async =>
      ((await SharedPreferences.getInstance()).getStringList(key(patientId)) ??
              [])
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
  Future<void> acknowledge(String patientId, int id) {
    final next = _writes.then((_) => _save(patientId, id));
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _save(String patientId, int id) async {
    final ids = await read(patientId)
      ..add(id);
    final saved = await (await SharedPreferences.getInstance()).setStringList(
      key(patientId),
      ids.map((id) => '$id').toList(),
    );
    if (!saved) throw StateError('Acknowledgement was not saved');
  }

  static bool actionable(AlertItem alert) =>
      {
        'help',
        'miss',
        'alert',
        'refill',
        'prescription',
        'done',
        'shared',
        'past',
      }.contains(alert.type) &&
      !(alert.type == 'alert' && alert.desc.contains('모두 정상이었어요'));
}

final guardianAlertRevisionProvider = StateProvider<int>((ref) => 0);
final guardianAlertRepositoryProvider = Provider<AlertRepository>(
  (ref) => AlertRepository(),
);
final guardianUnreadCountProvider = FutureProvider.family<int, String>((
  ref,
  owner,
) async {
  ref.watch(guardianAlertRevisionProvider);
  final overview = await ref.watch(careOverviewProvider.future);
  var count = 0;
  final inbox = GuardianAlertInbox(owner);
  for (final patient in overview.patients) {
    final alerts = await ref
        .read(guardianAlertRepositoryProvider)
        .fetch(patient.patientId);
    if (alerts == null) throw StateError('Unread count unavailable');
    final acknowledged = await inbox.read(patient.patientId);
    count += alerts
        .where(
          (a) =>
              GuardianAlertInbox.actionable(a) &&
              !acknowledged.contains(GuardianAlertInbox.identity(a)),
        )
        .length;
  }
  return count;
});
