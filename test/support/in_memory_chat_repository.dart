import 'dart:async';

import 'package:astrum/features/oracle/data/chat_repository.dart';
import 'package:astrum/features/oracle/domain/chat_limits.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';

/// [ChatRepository] em memoria para testes de controller (sem Firebase).
/// Emite o estado atual a cada nova assinatura e a cada mudanca.
class InMemoryChatRepository implements ChatRepository {
  final _convs = <String, Map<String, _Conv>>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  int _ids = 0;
  int syncCalls = 0;

  Map<String, _Conv> _of(String uid) => _convs.putIfAbsent(uid, () => {});

  List<ChatConversation> _list(String uid) {
    final all = _of(uid).values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      for (final c in all.take(50))
        ChatConversation(
          id: c.id,
          title: c.title,
          messages: const [],
          updatedAt: c.updatedAt,
          messageCount: c.messages.length,
        ),
    ];
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  @override
  Stream<List<ChatConversation>> watchConversations(String uid) =>
      _watch(() => _list(uid));

  @override
  Stream<List<ChatTurnStored>> watchMessages(String uid, String convId,
          {int limit = 500}) =>
      _watch(() {
        final m = _of(uid)[convId]?.messages ?? const <ChatTurnStored>[];
        return m.length > limit ? m.sublist(m.length - limit) : List.of(m);
      });

  @override
  Future<void> appendMessage(
    String uid, {
    required String convId,
    required ChatTurnStored message,
    required DateTime updatedAt,
    String? title,
    bool isNew = false,
  }) async {
    final convs = _of(uid);
    var c = convs[convId];
    if (isNew) {
      c = convs[convId] =
          _Conv(convId, titleFrom(title ?? message.text), updatedAt);
    } else if (c == null) {
      throw StateError('not-found');
    }
    c.messages.add(message);
    c.updatedAt = updatedAt;
    _changes.add(null);
  }

  @override
  Future<int?> remoteMessageCount(String uid, String convId,
          {bool fromServer = false}) async =>
      _of(uid)[convId]?.messages.length;

  @override
  Future<void> deleteConversation(String uid, String convId) async {
    _of(uid).remove(convId);
    _changes.add(null);
  }

  @override
  Future<void> deleteAllConversations(String uid) async {
    _of(uid).clear();
    _changes.add(null);
  }

  @override
  Future<void> waitForSync() async => syncCalls++;

  @override
  String newId() => 'id${_ids++}';
}

class _Conv {
  _Conv(this.id, this.title, this.updatedAt);
  final String id;
  final String title;
  DateTime updatedAt;
  final messages = <ChatTurnStored>[];
}
