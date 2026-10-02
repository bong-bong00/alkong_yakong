import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores existing answers only. Never generates or combines medical advice.
class PharmacistAnswerCache {
  static String canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${canonical(value[key])}').join(',')}}';
    }
    if (value is List) return '[${value.map(canonical).join(',')}]';
    return jsonEncode(value);
  }

  String _key(String user) =>
      'pharmacist_answers_v1_${Uri.encodeComponent(user)}';

  Future<List<Map<String, dynamic>>> _load(String user) async {
    if (user.isEmpty) return [];
    try {
      final prefs = await SharedPreferences.getInstance();
      return (jsonDecode(prefs.getString(_key(user)) ?? '[]') as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> find(
    String user,
    String request, {
    String? context,
    Duration? maxAge,
    DateTime? now,
  }) async {
    for (final record in await _load(user)) {
      if (record['request'] != request) continue;
      if (context != null && record['context'] != context) continue;
      final saved = DateTime.tryParse(record['savedAt']?.toString() ?? '');
      if (saved == null) continue;
      final age = (now ?? DateTime.now()).difference(saved);
      if (maxAge != null && (age.isNegative || age > maxAge)) continue;
      return record;
    }
    return null;
  }

  Future<void> save(
    String user,
    String request,
    String context,
    Map<String, dynamic> response,
  ) async {
    if (user.isEmpty ||
        (response['reply']?.toString().trim() ?? '').isEmpty ||
        (response['sources'] as List? ?? []).isEmpty) {
      return;
    }
    final records = await _load(user);
    records.removeWhere(
      (item) => item['request'] == request && item['context'] == context,
    );
    records.insert(0, {
      'request': request,
      'context': context,
      'savedAt': DateTime.now().toIso8601String(),
      'response': response,
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(user), jsonEncode(records.take(80).toList()));
  }
}
