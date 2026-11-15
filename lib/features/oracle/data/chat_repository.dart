import 'package:astrum/features/oracle/domain/chat_models.dart';

/// Historico do chat do oraculo, por snapshot da lista inteira (assim a
/// gravacao em shared_preferences segue byte a byte igual a de antes).
/// `load` ja e Future para a troca de fonte da etapa 10.
abstract interface class ChatRepository {
  /// Conversas do [uid]; sem historico, uma conversa vazia.
  Future<List<ChatConversation>> load(String uid);

  Future<void> save(String uid, List<ChatConversation> all);

  /// Conversa nova e vazia, titulada "Conversa [index]".
  ChatConversation create(int index);
}
