import 'dart:convert';

import 'package:astrum/features/oracle/data/legacy_chat_repository.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LegacyChatStore implements LegacyChatRepository {
  LegacyChatStore(this._prefs);

  final SharedPreferences _prefs;
  static const _uuid = Uuid();

  String _key(String uid) => 'astrum.chat.$uid';
  String _bakKey(String uid) => '${_key(uid)}.bak';
  String _flagKey(String uid) => 'astrum.chat.migrated.$uid';

  /// JSON cru do legado (null = ausente), usado so pelo migrador.
  String? rawJson(String uid) => _prefs.getString(_key(uid));

  /// Marca de migracao ('done', 'empty' ou 'corrupt'); null = nao migrado.
  String? migratedFlag(String uid) => _prefs.getString(_flagKey(uid));

  Future<void> markMigrated(String uid, String flag) =>
      _prefs.setString(_flagKey(uid), flag);

  /// Copia o JSON cru para `<chave>.bak` (nunca apaga o original).
  Future<void> backup(String uid, String raw) =>
      _prefs.setString(_bakKey(uid), raw);

  /// Remove o original; so depois de [backup] e da conferencia no servidor.
  Future<void> removeOriginal(String uid) => _prefs.remove(_key(uid));

  @override
  Future<List<ChatConversation>> load(String uid) async {
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
              .map((m) =>
                  ChatTurnStored.fromJson(Map<String, dynamic>.from(m as Map)))
              .toList(),
        );
      }).toList();
    } catch (_) {
      return [_empty(1)];
    }
  }

  @override
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

  @override
  ChatConversation create(int index) => ChatConversation(
        id: _uuid.v4(),
        title: 'Conversa $index',
        messages: const [],
      );

  ChatConversation _empty(int index) => create(index);
}
