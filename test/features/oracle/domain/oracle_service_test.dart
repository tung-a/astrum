import 'package:astrum/features/oracle/domain/oracle_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = OracleService();

  test('localReply responde sobre a lua', () {
    final reply = service.localReply(prompt: 'Como está a lua?', sign: 'Leão');
    expect(reply, contains('Hoje a lua está'));
    expect(reply, contains('Leão'));
  });

  test('localReply responde sobre amor citando o signo', () {
    final reply = service.localReply(prompt: 'Fale sobre amor', sign: 'Touro');
    expect(reply, contains('Touro'));
  });

  test('localReply usa fallback e nunca retorna vazio', () {
    final reply = service.localReply(prompt: 'xyz');
    expect(reply.trim(), isNotEmpty);
  });

  test('complete devolve localReply sem rede', () async {
    final reply = await service.complete(prompt: 'lua', sign: 'Áries');
    expect(reply, contains('Hoje a lua está'));
  });
}
