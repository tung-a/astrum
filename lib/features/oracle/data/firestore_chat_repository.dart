import 'dart:async';

import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/features/oracle/data/chat_repository.dart';
import 'package:astrum/features/oracle/domain/chat_limits.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// [ChatRepository] sobre o Firestore. Respeita as regras: no maximo uma
/// mensagem por batch, junto com a escrita da conversa (contador +1).
/// Nenhum texto de conversa vai a log ou a mensagem de erro.
class FirestoreChatRepository implements ChatRepository {
  FirestoreChatRepository(this._db,
      {this.deleteCommitTimeout = const Duration(seconds: 15)});

  /// Offline o `commit` de exclusao nunca completa: passado este prazo vira
  /// [ChatOfflineException] (a nova tentativa e idempotente).
  final Duration deleteCommitTimeout;

  final FirebaseFirestore _db;
  static const _uuid = Uuid();

  /// Tamanho do lote de exclusao (teto do Firestore e 500 por batch).
  static const _deleteBatch = 400;
  static const _listLimit = 50;

  CollectionReference<Map<String, dynamic>> _convs(String uid) =>
      _db.collection('users').doc(uid).collection('conversations');

  CollectionReference<Map<String, dynamic>> _msgs(String uid, String convId) =>
      _convs(uid).doc(convId).collection('messages');

  @override
  Stream<List<ChatConversation>> watchConversations(String uid) => _convs(uid)
      .orderBy('updatedAt', descending: true)
      .limit(_listLimit)
      .snapshots()
      .map((s) => [for (final d in s.docs) _conversation(d)]);

  @override
  Stream<List<ChatTurnStored>> watchMessages(String uid, String convId,
          {int limit = chatMessagesMax}) =>
      _msgs(uid, convId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => [for (final d in s.docs.reversed) _message(d)]);

  @override
  Future<void> appendMessage(
    String uid, {
    required String convId,
    required ChatTurnStored message,
    required DateTime updatedAt,
    String? title,
    bool isNew = false,
  }) {
    final id = message.id;
    final createdAt = message.createdAt;
    if (id == null || createdAt == null) {
      throw ArgumentError('message precisa de id e createdAt');
    }
    final text = clampText(message.text);
    if (text.isEmpty) throw ArgumentError('mensagem vazia');
    final role = message.role == 'model' ? 'model' : 'user';

    final batch = _db.batch();
    final convRef = _convs(uid).doc(convId);
    if (isNew) {
      batch.set(convRef, {
        'title': titleFrom(title ?? text),
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'messageCount': 1,
        'schemaVersion': chatSchemaVersion,
      });
    } else {
      batch.update(convRef, {
        'updatedAt': Timestamp.fromDate(updatedAt),
        'messageCount': FieldValue.increment(1),
      });
    }
    batch.set(_msgs(uid, convId).doc(id), {
      'role': role,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
    });
    return batch.commit();
  }

  @override
  Future<int?> remoteMessageCount(String uid, String convId,
      {bool fromServer = false}) async {
    final snap = await _convs(uid)
        .doc(convId)
        .get(fromServer ? const GetOptions(source: Source.server) : null);
    if (!snap.exists) return null;
    return (snap.data()?['messageCount'] as num?)?.toInt() ?? 0;
  }

  /// Leitura de pagina SEMPRE do servidor (exclusao nao pode se basear em
  /// cache parcial). Offline falha com [ChatOfflineException]. Sobrescrevivel
  /// so em teste.
  @visibleForTesting
  Future<QuerySnapshot<Map<String, dynamic>>> getServerPage(
      Query<Map<String, dynamic>> query) async {
    try {
      return await query.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        throw const ChatOfflineException();
      }
      rethrow;
    }
  }

  /// Commit do lote de exclusao. Sobrescrevivel so em teste.
  @visibleForTesting
  Future<void> commitDelete(WriteBatch batch) => batch.commit();

  /// Filhos primeiro: pagina as mensagens do servidor ate uma pagina vazia e
  /// so entao apaga a conversa. Offline falha na 1a leitura, antes de apagar
  /// qualquer coisa. Idempotente (conversa ja apagada: 1 leitura vazia).
  @override
  Future<void> deleteConversation(String uid, String convId) async {
    final msgs = _msgs(uid, convId);
    while (true) {
      final page = await getServerPage(msgs.limit(_deleteBatch));
      if (page.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in page.docs) {
        batch.delete(d.reference);
      }
      try {
        await commitDelete(batch).timeout(deleteCommitTimeout);
      } on TimeoutException {
        // Offline o commit nao completa; a nova tentativa e idempotente.
        throw const ChatOfflineException();
      }
    }
    await _convs(uid).doc(convId).delete();
  }

  @override
  Future<void> deleteAllConversations(String uid) async {
    while (true) {
      final page = await getServerPage(_convs(uid).limit(_listLimit));
      if (page.docs.isEmpty) break;
      for (final d in page.docs) {
        await deleteConversation(uid, d.id);
      }
    }
  }

  @override
  Future<void> waitForSync() => _db.waitForPendingWrites();

  @override
  String newId() => _uuid.v4();

  ChatConversation _conversation(
          QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      ChatConversation(
        id: d.id,
        title: d.data()['title'] as String? ?? 'Conversa',
        messages: const [],
        updatedAt: _date(d.data()['updatedAt']),
        messageCount: (d.data()['messageCount'] as num?)?.toInt() ?? 0,
      );

  ChatTurnStored _message(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      ChatTurnStored(
        id: d.id,
        role: d.data()['role'] == 'model' ? 'model' : 'user',
        text: d.data()['text'] as String? ?? '',
        createdAt: _date(d.data()['createdAt']),
      );

  DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;
}
