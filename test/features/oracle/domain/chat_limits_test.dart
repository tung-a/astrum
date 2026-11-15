import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/features/oracle/domain/chat_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('titleFrom', () {
    test('mensagem curta vira o titulo (sem espacos nas pontas)', () {
      expect(titleFrom('  Olá, oráculo  '), 'Olá, oráculo');
    });

    test('corta em 80 unidades UTF-16', () {
      expect(titleFrom('a' * 200).length, chatTitleMax);
      expect(titleFrom('a' * 80), 'a' * 80);
    });

    test('nao parte par substituto (emoji) na fronteira', () {
      // 79 letras + emoji (2 unidades): o corte em 80 cairia no meio.
      final t = titleFrom('${'a' * 79}\u{1F52E}resto');
      expect(t, 'a' * 79);
      // Emoji inteiro dentro do limite e mantido.
      final ok = titleFrom('${'a' * 78}\u{1F52E}resto');
      expect(ok, '${'a' * 78}\u{1F52E}');
      expect(ok.length, 80);
    });

    test('vazio vira "Conversa" (regra exige >= 1)', () {
      expect(titleFrom(''), 'Conversa');
      expect(titleFrom('   \n'), 'Conversa');
    });
  });

  group('clampText', () {
    test('texto dentro do limite fica igual', () {
      expect(clampText('oi'), 'oi');
      expect(clampText('a' * chatTextMax), 'a' * chatTextMax);
    });

    test('trunca em 10000 e nao parte emoji', () {
      expect(clampText('a' * 10001).length, chatTextMax);
      final t = clampText('${'a' * 9999}\u{1F52E}');
      expect(t, 'a' * 9999);
    });
  });
}
