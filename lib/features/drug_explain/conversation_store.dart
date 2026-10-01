import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-local history, partitioned by the signed-in user. No health profile copy.
class PharmacistConversationStore {
  String _key(String userId) =>
      'pharmacist_conversations_v1_${Uri.encodeComponent(userId)}';

  Future<List<Map<String, dynamic>>> load(String userId) async {
    if (userId.trim().isEmpty) return [];
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(userId));
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List;
    final records = decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    records.sort(
      (a, b) => (b['updatedAt'] as String).compareTo(a['updatedAt'] as String),
    );
    return records;
  }

  Future<void> save(String userId, Map<String, dynamic> conversation) async {
    if (userId.trim().isEmpty) return;
    final records = await load(userId);
    records.removeWhere((item) => item['id'] == conversation['id']);
    records.insert(0, conversation);
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_key(userId), jsonEncode(records))) {
      throw StateError('Conversation could not be saved');
    }
  }
}
