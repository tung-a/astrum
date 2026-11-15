import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/features/oracle/domain/chat_limits.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';

class ImportMessage {
  const ImportMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
  });
  final String id;
  final String role;
  final String text;
  final DateTime createdAt;
}

class ImportConversation {
  const ImportConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ImportMessage> messages;
}

String _msgId(int index) => 'm${index.toString().padLeft(4, '0')}';

/// Plano de importacao do historico legado (puro, sem Firebase).
///
/// Descarta mensagens vazias e conversas sem mensagens (eram rascunhos),
/// normaliza `role` (fora de user/model vira user), trunca o texto, mantem so
/// as [chatMessagesMax] mensagens mais recentes de cada conversa (teto da
/// regra) e atribui ids `m0001...` pelo indice na lista ja filtrada. Datas
/// sinteticas: a conversa `i` de `N` recebe `updatedAt = now - (N-1-i) s` e a
/// mensagem `j` de `n` recebe `updatedAt - (n-j) ms` (estritamente crescente).
List<ImportConversation> planLegacyImport(
    List<ChatConversation> legacy, DateTime now) {
  final filtered = <(ChatConversation, List<ChatTurnStored>)>[];
  for (final c in legacy) {
    var msgs = [
      for (final m in c.messages)
        if (m.text.trim().isNotEmpty) m,
    ];
    if (msgs.isEmpty) continue;
    if (msgs.length > chatMessagesMax) {
      msgs = msgs.sublist(msgs.length - chatMessagesMax);
    }
    filtered.add((c, msgs));
  }

  final total = filtered.length;
  final out = <ImportConversation>[];
  for (var i = 0; i < total; i++) {
    final (c, msgs) = filtered[i];
    final updatedAt = now.subtract(Duration(seconds: total - 1 - i));
    final n = msgs.length;
    final planned = <ImportMessage>[
      for (var j = 0; j < n; j++)
        ImportMessage(
          id: _msgId(j + 1),
          role: msgs[j].role == 'model' ? 'model' : 'user',
          text: clampText(msgs[j].text),
          createdAt: updatedAt.subtract(Duration(milliseconds: n - j)),
        ),
    ];
    out.add(ImportConversation(
      id: c.id,
      title: titleFrom(c.title),
      createdAt: planned.first.createdAt,
      updatedAt: updatedAt,
      messages: planned,
    ));
  }
  return out;
}
