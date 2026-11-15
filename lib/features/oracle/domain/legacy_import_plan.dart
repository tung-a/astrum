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
/// normaliza `role` (fora de user/model vira user) e trunca o texto. Conversas
/// com mais de [chatMessagesMax] mensagens (teto da regra) sao DIVIDIDAS em
/// partes de ate 500, em ordem: a parte 1 mantem o id e o titulo; a parte `p`
/// (p >= 2) usa id `<id>-p<p>` e titulo `<titulo> (parte p)` (<= 80 unidades
/// UTF-16). Ids de mensagem `m0001...` pelo indice dentro de cada parte.
///
/// Ids de conversa sao unicos no plano: um id ja usado (legado repetido, ou
/// colisao com um `<id>-pN` gerado) recebe o sufixo `-d2`, `-d3`... em ordem.
///
/// Datas sinteticas ancoradas no INICIO ([base]), para que anexar conversas ou
/// mensagens ao fim do legado nunca mude a data do que ja foi enviado: cada
/// parte conta como uma conversa; a parte `i` (0-based, em ordem; a ultima e a
/// mais recente, a de maior `updatedAt`) recebe `updatedAt = base + i s` e
/// `createdAt = updatedAt` (inicio da parte); a mensagem `j` (0-based) recebe
/// `inicio + j ms` (< 500 ms, sempre antes da parte seguinte). Deterministico,
/// entao a retomada pela contagem de mensagens de cada conversa continua valida.
List<ImportConversation> planLegacyImport(
    List<ChatConversation> legacy, DateTime base) {
  final parts = <(String, String, List<ChatTurnStored>)>[];
  final used = <String>{};
  String unique(String id) {
    var out = id;
    for (var n = 2; !used.add(out); n++) {
      out = '$id-d$n';
    }
    return out;
  }

  for (final c in legacy) {
    final msgs = [
      for (final m in c.messages)
        if (m.text.trim().isNotEmpty) m,
    ];
    if (msgs.isEmpty) continue;
    final count = (msgs.length + chatMessagesMax - 1) ~/ chatMessagesMax;
    for (var p = 0; p < count; p++) {
      final start = p * chatMessagesMax;
      final end = start + chatMessagesMax;
      parts.add((
        unique(p == 0 ? c.id : '${c.id}-p${p + 1}'),
        p == 0
            ? titleFrom(c.title)
            : titleWithSuffix(c.title, ' (parte ${p + 1})'),
        msgs.sublist(start, end > msgs.length ? msgs.length : end),
      ));
    }
  }

  final out = <ImportConversation>[];
  for (var i = 0; i < parts.length; i++) {
    final (id, title, msgs) = parts[i];
    final startAt = base.add(Duration(seconds: i));
    final planned = <ImportMessage>[
      for (var j = 0; j < msgs.length; j++)
        ImportMessage(
          id: _msgId(j + 1),
          role: msgs[j].role == 'model' ? 'model' : 'user',
          text: clampText(msgs[j].text),
          createdAt: startAt.add(Duration(milliseconds: j)),
        ),
    ];
    out.add(ImportConversation(
      id: id,
      title: title,
      createdAt: startAt,
      updatedAt: startAt,
      messages: planned,
    ));
  }
  return out;
}
