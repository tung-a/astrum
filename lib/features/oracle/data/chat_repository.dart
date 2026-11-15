import 'package:astrum/features/oracle/domain/chat_models.dart';

/// Operacao que exige o servidor (ex.: exclusao) tentada sem conexao.
class ChatOfflineException implements Exception {
  const ChatOfflineException();
  @override
  String toString() =>
      'ChatOfflineException: sem conexao com o servidor; nada foi apagado.';
}

/// Historico do oraculo na nuvem (users/{uid}/conversations), incremental e
/// por streams (docs/architecture/step10-chat-sync.md, secao 4.2). Ainda nao
/// esta ligado ao controller: o chat segue no armazenamento local legado.
abstract interface class ChatRepository {
  /// Ate 50 conversas, mais recente primeiro (`messages` vazio; so metadados).
  Stream<List<ChatConversation>> watchConversations(String uid);

  /// Ultimas [limit] mensagens (padrao 500), em ordem cronologica.
  Stream<List<ChatTurnStored>> watchMessages(String uid, String convId,
      {int limit = 500});

  /// Uma mensagem por batch (exigencia das regras). [isNew]: cria a conversa
  /// (titulo + createdAt) em vez de atualizar. Nao deve ser aguardado no
  /// fluxo da UI: offline o Future so completa com o servidor.
  /// [message] precisa de `id` e `createdAt`.
  Future<void> appendMessage(
    String uid, {
    required String convId,
    required ChatTurnStored message,
    required DateTime updatedAt,
    String? title,
    bool isNew = false,
  });

  /// `messageCount` da conversa; null = nao existe. Por padrao enxerga as
  /// escritas locais pendentes; [fromServer] exige o servidor (verificacao
  /// final da migracao) e falha offline.
  Future<int?> remoteMessageCount(String uid, String convId,
      {bool fromServer = false});

  /// Ids das mensagens existentes no SERVIDOR (ate o teto de 500 da regra);
  /// falha offline. Usado so pelo migrador para preencher lacunas.
  Future<Set<String>> remoteMessageIds(String uid, String convId);

  /// Apaga as mensagens (em lotes, lendo do servidor) e depois a conversa.
  /// Offline lanca [ChatOfflineException] sem apagar nada. Idempotente.
  Future<void> deleteConversation(String uid, String convId);

  /// Apaga todas as conversas do [uid], paginando ate esvaziar (nao so 50).
  Future<void> deleteAllConversations(String uid);

  /// Aguarda as escritas pendentes chegarem ao servidor.
  Future<void> waitForSync();

  String newId();
}
