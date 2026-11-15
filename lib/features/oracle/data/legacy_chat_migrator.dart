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

  /// Execucao unica por uid no processo: chamadas concorrentes (ex.: duas
  /// aberturas do oraculo) compartilham a mesma execucao e o mesmo resultado.
  static final _inFlight = <String, Future<MigrationResult>>{};

  Future<MigrationResult> run(String uid) {
    final running = _inFlight[uid];
    if (running != null) return running;
    final f = _run(uid).whenComplete(() {
      _inFlight.remove(uid);
    });
    return _inFlight[uid] = f;
  }

  Future<MigrationResult> _run(String uid) async {
    if (_legacy.migratedFlag(uid) != null) return MigrationResult.alreadyDone;

    final raw = _legacy.rawJson(uid);
    if (raw == null) {
      await _legacy.markMigrated(uid, 'empty');
      return MigrationResult.nothingToMigrate;
    }

    final parsed = _parse(raw);
    if (parsed == null) {
      // So marca `corrupt` com o .bak confirmado (original segue intacto).
      if (!await _legacy.backup(uid, raw)) return MigrationResult.incomplete;
      await _legacy.markMigrated(uid, 'corrupt');
      return MigrationResult.corrupt;
    }

    if (planLegacyImport(parsed, _now()).isEmpty) {
      // Lista vazia ou so rascunhos: nada a enviar.
      await _legacy.markMigrated(uid, 'empty');
      return MigrationResult.nothingToMigrate;
    }

    // Base das datas sinteticas: gravada na 1a tentativa e reutilizada nas
    // retomadas (ordem estavel entre tentativas).
    var baseMs = _legacy.migrationBase(uid);
    if (baseMs == null) {
      baseMs = _now().toUtc().millisecondsSinceEpoch;
      if (!await _legacy.setMigrationBase(uid, baseMs)) {
        return MigrationResult.incomplete;
      }
    }
    final plan = planLegacyImport(
        parsed, DateTime.fromMillisecondsSinceEpoch(baseMs, isUtc: true));

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

    // O legado mudou durante a migracao (ex.: uso do chat): nada e apagado; a
    // proxima abertura migra o que faltar.
    if (_legacy.rawJson(uid) != raw) return MigrationResult.incomplete;
    // Nunca remove o original sem o .bak confirmado.
    if (!await _legacy.backup(uid, raw)) return MigrationResult.incomplete;
    if (_legacy.backupJson(uid) != raw) return MigrationResult.incomplete;
    await _legacy.removeOriginal(uid);
    await _legacy.markMigrated(uid, 'done');
    await _legacy.clearMigrationBase(uid);
    return MigrationResult.migrated;
  }

  /// Leitura tolerante (como `ChatTurnStored.fromJson`): role/text atipicos,
  /// mensagens que nao sao mapa e ids invalidos nao corrompem o historico.
  /// So estrutura irrecuperavel (raiz nao e mapa, `conversations` nao e lista)
  /// devolve null.
  List<ChatConversation>? _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final list = decoded['conversations'];
      if (list == null) return const [];
      if (list is! List) return null;
      final out = <ChatConversation>[];
      for (var i = 0; i < list.length; i++) {
        final c = list[i];
        final map = c is Map ? c : const <Object?, Object?>{};
        final rawId = map['id'];
        final id = rawId is String && _validId(rawId) ? rawId : 'legacy-$i';
        final msgs = map['messages'];
        out.add(ChatConversation(
          id: id,
          title: map['title'] is String ? map['title'] as String : 'Conversa',
          messages: [
            if (msgs is List)
              for (final m in msgs)
                if (m is Map)
                  ChatTurnStored(
                    role: m['role'] is String ? m['role'] as String : 'user',
                    text: m['text'] is String ? m['text'] as String : '',
                  ),
          ],
        ));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Id valido de documento do Firestore (sem '/', nao vazio, nao '.'/'..').
  bool _validId(String id) =>
      id.isNotEmpty &&
      id.length <= 1500 &&
      !id.contains('/') &&
      id != '.' &&
      id != '..';

  ChatTurnStored _stored(ImportMessage m) => ChatTurnStored(
      id: m.id, role: m.role, text: m.text, createdAt: m.createdAt);

  /// Envia o que falta de [conv], uma mensagem por batch e sem aguardar cada
  /// commit (a fila do Firestore preserva a ordem). Se outro aparelho avancar
  /// (`permission-denied`), relê a contagem e continua. Esgotadas as rodadas,
  /// lista os ids existentes no servidor e envia so os que faltam. Devolve
  /// false quando nao deu para concluir agora.
  Future<bool> _sendConversation(String uid, ImportConversation conv) async {
    final n = conv.messages.length;
    for (var round = 0; round < maxRounds; round++) {
      final k = await _repo.remoteMessageCount(uid, conv.id);
      if (k != null && k >= n) return true;

      final settled = <Future<String?>>[];
      for (var j = k ?? 0; j < n; j++) {
        final m = conv.messages[j];
        settled.add(_settle(_repo.appendMessage(
          uid,
          convId: conv.id,
          message: _stored(m),
          updatedAt: j == n - 1 ? conv.updatedAt : m.createdAt,
          title: conv.title,
          isNew: k == null && j == 0,
        )));
      }
      final codes = await Future.wait(settled).timeout(syncTimeout);
      final failed = codes.whereType<String>().toList();
      if (failed.isEmpty) return true;
      if (failed.any((c) => c != 'permission-denied')) return false;
      // permission-denied: outro aparelho avancou; relê a contagem.
    }
    return _fillGaps(uid, conv);
  }

  /// Lacuna permanente: le do servidor os ids existentes e envia so os que
  /// faltam (um por batch; a conversa ja existe se ha ids no servidor).
  Future<bool> _fillGaps(String uid, ImportConversation conv) async {
    final existing = await _repo.remoteMessageIds(uid, conv.id);
    final missing = [
      for (final m in conv.messages)
        if (!existing.contains(m.id)) m,
    ];
    if (missing.isEmpty) return true;
    final settled = <Future<String?>>[];
    for (var i = 0; i < missing.length; i++) {
      settled.add(_settle(_repo.appendMessage(
        uid,
        convId: conv.id,
        message: _stored(missing[i]),
        updatedAt: conv.updatedAt,
        title: conv.title,
        isNew: existing.isEmpty && i == 0,
      )));
    }
    final codes = await Future.wait(settled).timeout(syncTimeout);
    return codes.whereType<String>().isEmpty;
  }

  /// Resultado do commit sem propagar texto: so o codigo do erro.
  Future<String?> _settle(Future<void> f) => f.then<String?>((_) => null,
      onError: (Object e) => e is FirebaseException ? e.code : 'error');
}
