import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/app_user.dart';

class ChatStore {
  ChatStore(this._prefs);

  final SharedPreferences _prefs;
  static const _uuid = Uuid();

  String _key(String uid) => 'astrum.chat.$uid';

  List<ChatConversation> load(String uid) {
    final raw = _prefs.getString(_key(uid));
    if (raw == null) return [_empty(1)];
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final list = decoded['conversations'] as List? ?? [];
      if (list.isEmpty) return [_empty(1)];
      return list.map((c) {
        final map = Map<String, dynamic>.from(c as Map);
        return ChatConversation(
          id: map['id'] as String,
          title: map['title'] as String? ?? 'Conversa',
          messages: ((map['messages'] as List?) ?? [])
              .map((m) => ChatTurnStored.fromJson(Map<String, dynamic>.from(m as Map)))
              .toList(),
        );
      }).toList();
    } catch (_) {
      return [_empty(1)];
    }
  }

  Future<void> save(String uid, List<ChatConversation> conversations) async {
    await _prefs.setString(
      _key(uid),
      jsonEncode({
        'conversations': conversations
            .map(
              (c) => {
                'id': c.id,
                'title': c.title,
                'messages': c.messages.map((m) => m.toJson()).toList(),
              },
            )
            .toList(),
      }),
    );
  }

  ChatConversation create(int index) => ChatConversation(
        id: _uuid.v4(),
        title: 'Conversa $index',
        messages: const [],
      );

  ChatConversation _empty(int index) => create(index);
}
