import 'package:astrum/core/firebase/rules_contract.dart';

/// Corta [s] em no maximo [max] unidades UTF-16 sem partir um par substituto
/// (emoji): se o corte cairia entre as duas metades, descarta a primeira.
String _cut(String s, int max) {
  if (s.length <= max) return s;
  var end = max;
  final last = s.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return s.substring(0, end);
}

/// Titulo de uma conversa nova: a primeira mensagem (sem espacos nas pontas),
/// cortada em [chatTitleMax]. Vazio vira "Conversa" (a regra exige >= 1).
String titleFrom(String firstMessage) {
  final t = _cut(firstMessage.trim(), chatTitleMax);
  return t.isEmpty ? 'Conversa' : t;
}

/// Texto de mensagem limitado a [chatTextMax] (sem partir par substituto).
String clampText(String text) => _cut(text, chatTextMax);
