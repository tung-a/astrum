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

  test('exatamente 500 mensagens: uma conversa so', () {
    final plan = planLegacyImport([
      c('a', [for (var i = 0; i < 500; i++) t('user', 'm$i')]),
    ], now);
    expect(plan, hasLength(1));
    expect(plan.single.messages, hasLength(chatMessagesMax));
  });

  test('mais de 500 mensagens: divide em partes de ate 500, sem perder nada',
      () {
    final plan = planLegacyImport([
      c('a', [for (var i = 0; i < 1203; i++) t('user', 'm$i')], title: 'Amor'),
      c('b', [t('user', 'x')]),
    ], now);
    expect(plan.map((p) => p.id), ['a', 'a-p2', 'a-p3', 'b']);
    expect(plan.map((p) => p.title),
        ['Amor', 'Amor (parte 2)', 'Amor (parte 3)', 'T']);
    expect(plan.map((p) => p.messages.length), [500, 500, 203, 1]);
    for (final p in plan) {
      expect(p.messages.first.id, 'm0001');
    }
    expect(plan[0].messages.first.text, 'm0');
    expect(plan[0].messages.last.text, 'm499');
    expect(plan[1].messages.first.text, 'm500');
    expect(plan[2].messages.last.text, 'm1202');
    expect(plan[2].messages.last.id, 'm0203');
    for (var i = 1; i < plan.length; i++) {
      expect(plan[i].updatedAt.isAfter(plan[i - 1].updatedAt), isTrue);
    }
    expect(plan.last.updatedAt, now);
  });

  test('titulo da parte respeita 80 unidades UTF-16 (sem partir emoji)', () {
    final long = '${'a' * 78}\u{1F52E}'; // 80 unidades
    final plan = planLegacyImport([
      c('a', [for (var i = 0; i < 501; i++) t('user', 'm$i')], title: long),
    ], now);
    expect(plan[0].title, long);
    expect(plan[1].title, '${'a' * 70} (parte 2)');
    final emoji = planLegacyImport([
      c('a', [for (var i = 0; i < 501; i++) t('user', 'm$i')],
          title: '${'a' * 69}\u{1F52E}'),
    ], now)[1]
        .title;
    expect(emoji, '${'a' * 69} (parte 2)'); // descartou o par cortado
    expect(emoji.length, lessThanOrEqualTo(chatTitleMax));
  });

  test('divisao e deterministica entre execucoes', () {
    final input = [
      c('a', [for (var i = 0; i < 700; i++) t('user', 'm$i')]),
    ];
    final a = planLegacyImport(input, now);
    final b = planLegacyImport(input, now);
    expect(a.map((p) => (p.id, p.title, p.messages.length)).toList(),
        b.map((p) => (p.id, p.title, p.messages.length)).toList());
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
