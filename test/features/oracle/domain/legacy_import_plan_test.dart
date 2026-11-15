import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:astrum/features/oracle/domain/legacy_import_plan.dart';
import 'package:flutter_test/flutter_test.dart';

ChatTurnStored t(String role, String text) =>
    ChatTurnStored(role: role, text: text);

ChatConversation c(String id, List<ChatTurnStored> m, {String title = 'T'}) =>
    ChatConversation(id: id, title: title, messages: m);

void main() {
  final now = DateTime.utc(2026, 11, 14, 12);

  test('lista vazia e conversas sem mensagem validas nao geram nada', () {
    expect(planLegacyImport(const [], now), isEmpty);
    expect(
        planLegacyImport([
          c('a', const []),
          c('b', [t('user', ''), t('model', '   ')]),
        ], now),
        isEmpty);
  });

  test('descarta mensagens vazias e numera m0001.. na lista filtrada', () {
    final plan = planLegacyImport([
      c('a', [t('user', 'oi'), t('model', ''), t('model', 'ola')]),
    ], now);
    expect(plan.single.messages.map((m) => m.id), ['m0001', 'm0002']);
    expect(plan.single.messages.map((m) => m.text), ['oi', 'ola']);
  });

  test('role fora de user/model vira user', () {
    final plan = planLegacyImport([
      c('a', [t('system', 'x'), t('model', 'y'), t('', 'z')]),
    ], now);
    expect(plan.single.messages.map((m) => m.role), ['user', 'model', 'user']);
  });

  test('trunca texto longo', () {
    final plan = planLegacyImport([
      c('a', [t('user', 'a' * 12000)]),
    ], now);
    expect(plan.single.messages.single.text.length, chatTextMax);
  });

  test('titulo respeita o limite e nunca fica vazio', () {
    final plan = planLegacyImport([
      c('a', [t('user', 'x')], title: 'b' * 120),
      c('b', [t('user', 'x')], title: ''),
    ], now);
    expect(plan[0].title.length, chatTitleMax);
    expect(plan[1].title, 'Conversa');
  });

  test(
      'datas: ultima conversa e a mais recente; mensagens estritamente '
      'crescentes e <= updatedAt', () {
    final plan = planLegacyImport([
      c('a', [t('user', '1'), t('model', '2')]),
      c('b', [t('user', '3'), t('model', '4'), t('user', '5')]),
      c('vazia', const []),
      c('d', [t('user', '6')]),
    ], now);
    expect(plan.map((p) => p.id), ['a', 'b', 'd']);
    expect(plan.last.updatedAt, now);
    expect(plan[1].updatedAt, now.subtract(const Duration(seconds: 1)));
    expect(plan[0].updatedAt, now.subtract(const Duration(seconds: 2)));
    for (final p in plan) {
      for (var i = 1; i < p.messages.length; i++) {
        expect(p.messages[i].createdAt.isAfter(p.messages[i - 1].createdAt),
            isTrue);
      }
      expect(p.messages.last.createdAt.isBefore(p.updatedAt), isTrue);
      expect(p.createdAt, p.messages.first.createdAt);
    }
  });

  test('mais de 500 mensagens: mantem as 500 mais recentes', () {
    final plan = planLegacyImport([
      c('a', [for (var i = 0; i < 520; i++) t('user', 'm$i')]),
    ], now);
    final msgs = plan.single.messages;
    expect(msgs, hasLength(chatMessagesMax));
    expect(msgs.first.text, 'm20');
    expect(msgs.first.id, 'm0001');
    expect(msgs.last.id, 'm0500');
  });

  test('e deterministico (mesma entrada, mesmo plano)', () {
    final input = [
      c('a', [t('user', 'x'), t('model', 'y')]),
    ];
    final a = planLegacyImport(input, now).single;
    final b = planLegacyImport(input, now).single;
    expect(a.messages.map((m) => (m.id, m.createdAt)).toList(),
        b.messages.map((m) => (m.id, m.createdAt)).toList());
  });
}
