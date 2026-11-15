import 'dart:async';
import 'dart:convert';

import 'package:astrum/features/oracle/data/chat_repository.dart';
import 'package:astrum/features/oracle/data/legacy_chat_store.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:astrum/features/oracle/domain/legacy_import_plan.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum MigrationResult {
  /// Ja migrado antes (flag presente); nada foi feito.
  alreadyDone,

  /// Sem legado (ausente, vazio ou so rascunhos); flag gravada.
  nothingToMigrate,

  /// JSON invalido: copiado para `.bak`, flag `corrupt`, original intacto.
  corrupt,

  /// Tudo conferido no servidor; `.bak` gravado e original removido.
  migrated,

  /// Falha, timeout ou divergencia: nada apagado, repete na proxima abertura.
  incomplete,
}

/// Migra o historico legado (shared_preferences) para o Firestore
/// (docs/architecture/step10-chat-sync.md, secao 5). Retomavel pela contagem
/// de mensagens do servidor, idempotente e sem apagar nada antes da conferencia
/// de `messageCount` no servidor. Nao esta ligado ao app.
///
/// Nenhum texto de conversa vai a log ou a excecao.
class LegacyChatMigrator {
  LegacyChatMigrator({
    required LegacyChatStore legacy,
    required ChatRepository repository,
    DateTime Function()? now,
    this.syncTimeout = const Duration(seconds: 30),
    this.maxRounds = 5,
  })  : _legacy = legacy,
        _repo = repository,
        _now = now ?? DateTime.now;

  final LegacyChatStore _legacy;
  final ChatRepository _repo;
  final DateTime Function() _now;
  final Duration syncTimeout;

  /// Tentativas por conversa quando outro aparelho avanca em paralelo.
  final int maxRounds;

  Future<MigrationResult> run(String uid) async {
    if (_legacy.migratedFlag(uid) != null) return MigrationResult.alreadyDone;

    final raw = _legacy.rawJson(uid);
    if (raw == null) {
      await _legacy.markMigrated(uid, 'empty');
      return MigrationResult.nothingToMigrate;
    }

    final parsed = _parse(raw);
    if (parsed == null) {
      await _legacy.backup(uid, raw);
      await _legacy.markMigrated(uid, 'corrupt');
      return MigrationResult.corrupt;
    }

    final plan = planLegacyImport(parsed, _now());
    if (plan.isEmpty) {
      // Lista vazia ou so rascunhos: nada a enviar.
      await _legacy.markMigrated(uid, 'empty');
      return MigrationResult.nothingToMigrate;
    }

    try {
      for (final conv in plan) {
        if (!await _sendConversation(uid, conv)) {
          return MigrationResult.incomplete;
        }
      }
      await _repo.waitForSync().timeout(syncTimeout);
      for (final conv in plan) {
        final count =
            await _repo.remoteMessageCount(uid, conv.id, fromServer: true);
        if (count != conv.messages.length) return MigrationResult.incomplete;
      }
    } on TimeoutException {
      return MigrationResult.incomplete;
    } catch (_) {
      return MigrationResult.incomplete;
    }

    await _legacy.backup(uid, raw);
    await _legacy.removeOriginal(uid);
    await _legacy.markMigrated(uid, 'done');
    return MigrationResult.migrated;
  }

  /// Leitura estrita: qualquer formato inesperado devolve null (corrompido).
  List<ChatConversation>? _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final list = decoded['conversations'];
      if (list == null) return const [];
      if (list is! List) return null;
      return [
        for (final c in list)
          ChatConversation(
            id: (c as Map)['id'] as String,
            title: c['title'] as String? ?? 'Conversa',
            messages: [
              for (final m in (c['messages'] as List? ?? const []))
                ChatTurnStored(
                  role: (m as Map)['role'] as String? ?? 'user',
                  text: m['text'] as String? ?? '',
                ),
            ],
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Envia o que falta de [conv], uma mensagem por batch e sem aguardar cada
  /// commit (a fila do Firestore preserva a ordem). Se outro aparelho avancar
  /// (`permission-denied`), relê a contagem e continua. Devolve false quando
  /// nao deu para concluir agora (timeout ou erro que nao e concorrencia).
  Future<bool> _sendConversation(String uid, ImportConversation conv) async {
    final n = conv.messages.length;
    for (var round = 0; round < maxRounds; round++) {
      final k = await _repo.remoteMessageCount(uid, conv.id);
      if (k != null && k >= n) return true;

      final settled = <Future<String?>>[];
      for (var j = k ?? 0; j < n; j++) {
        final m = conv.messages[j];
        final f = _repo.appendMessage(
          uid,
          convId: conv.id,
          message: ChatTurnStored(
              id: m.id, role: m.role, text: m.text, createdAt: m.createdAt),
          updatedAt: j == n - 1 ? conv.updatedAt : m.createdAt,
          title: conv.title,
          isNew: k == null && j == 0,
        );
        // Resultado do commit sem propagar texto: so o codigo do erro.
        settled.add(f.then<String?>((_) => null,
            onError: (Object e) => e is FirebaseException ? e.code : 'error'));
      }
      final codes = await Future.wait(settled).timeout(syncTimeout);
      final failed = codes.whereType<String>().toList();
      if (failed.isEmpty) return true;
      if (failed.any((c) => c != 'permission-denied')) return false;
      // permission-denied: outro aparelho avancou; relê a contagem.
    }
    return false;
  }
}
