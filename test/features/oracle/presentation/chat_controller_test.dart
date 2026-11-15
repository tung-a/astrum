import 'dart:async';
import 'dart:convert';

import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:astrum/features/oracle/presentation/chat_controller.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/make_container.dart';

void main() {
  late FakeChatRepository chats;
  late FakeOracleService oracle;
  late FakeAnalytics analytics;

  setUp(() {
    chats = FakeChatRepository();
    oracle = FakeOracleService(reply: 'resposta do oraculo');
    analytics = FakeAnalytics();
  });

  Future<ProviderContainer> setup({
    bool loggedIn = true,
    bool hydrate = true,
  }) async {
    final c = await makeContainer(
      user: loggedIn ? testUser() : null,
      overrides: [
        chatRepositoryProvider.overrideWithValue(chats),
        oracleServiceProvider.overrideWithValue(oracle),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
    );
    addTearDown(c.dispose);
    // Mantem o autoDispose vivo.
    c.listen(chatControllerProvider, (_, __) {});
    if (hydrate) await c.read(chatControllerProvider.notifier).hydrate();
    return c;
  }

  ChatController ctl(ProviderContainer c) =>
      c.read(chatControllerProvider.notifier);
  ChatState st(ProviderContainer c) => c.read(chatControllerProvider);

  group('hydrate', () {
    test('carrega do repositorio, indice 0, e e idempotente', () async {
      final c = await setup(hydrate: false);
      expect(st(c).hydrated, isFalse);
      expect(st(c).current.id, 'x'); // placeholder antes de hidratar

      await ctl(c).hydrate();
      await ctl(c).hydrate();

      expect(chats.loads, ['u1']);
      expect(st(c).hydrated, isTrue);
      expect(st(c).conversations.single.id, 'conv-1');
      expect(st(c).index, 0);
    });

    test('sem perfil nao carrega', () async {
      final c = await setup(loggedIn: false);

      expect(chats.loads, isEmpty);
      expect(st(c).hydrated, isFalse);
    });

    test('reabrir a tela (novo controller) recarrega o historico salvo',
        () async {
      final c1 = await setup();
      await ctl(c1).send('Oi');
      c1.dispose();

      final c2 = await setup();

      expect(chats.loads, ['u1', 'u1']);
      expect(st(c2).current.messages.map((m) => m.text),
          ['Oi', 'resposta do oraculo']);
    });
  });

  test('takePendingPrompt devolve e limpa o provider', () async {
    final c = await setup();
    c.read(pendingOraclePromptProvider.notifier).state = 'pergunta pronta';

    expect(ctl(c).takePendingPrompt(), 'pergunta pronta');
    expect(c.read(pendingOraclePromptProvider), isNull);
    expect(ctl(c).takePendingPrompt(), isNull);
  });

  group('send', () {
    test('texto vazio ou so espacos e ignorado', () async {
      final c = await setup();

      await ctl(c).send('');
      await ctl(c).send('   ');

      expect(chats.saves, isEmpty);
      expect(oracle.calls, isEmpty);
      expect(st(c).loading, isFalse);
    });

    test('1a mensagem vira o titulo; usuario, resposta, analytics e 2 saves',
        () async {
      final c = await setup();

      await ctl(c).send('  Qual a energia de hoje?  ');

      final conv = st(c).current;
      expect(conv.title, 'Qual a energia de hoje?');
      expect(conv.messages.map((m) => (m.role, m.text)), [
        ('user', 'Qual a energia de hoje?'),
        ('model', 'resposta do oraculo'),
      ]);
      expect(oracle.calls.single.prompt, 'Qual a energia de hoje?');
      expect(analytics.events, ['send_message_chat']);
      expect(st(c).loading, isFalse);
      // Caracterizacao: 2 gravacoes por mensagem, ambas da lista inteira.
      expect(chats.saves, hasLength(2));
      expect(chats.saves[0].all.single.messages, hasLength(1));
      expect(chats.saves[1].all.single.messages, hasLength(2));
      expect(chats.saves.map((s) => s.uid), ['u1', 'u1']);
    });

    test('2a mensagem mantem o titulo', () async {
      final c = await setup();

      await ctl(c).send('Primeira');
      await ctl(c).send('Segunda');

      expect(st(c).current.title, 'Primeira');
      expect(st(c).current.messages, hasLength(4));
      expect(chats.saves, hasLength(4));
    });

    test('envio durante uma resposta em andamento e ignorado', () async {
      final gate = Completer<String>();
      oracle.completer = gate;
      final c = await setup();

      final first = ctl(c).send('Primeira');
      await Future<void>.delayed(Duration.zero);
      expect(st(c).loading, isTrue);
      await ctl(c).send('Segunda');
      gate.complete('ok');
      await first;

      expect(oracle.calls, hasLength(1));
      expect(st(c).current.messages, hasLength(2));
    });
  });

  group('newConversation e select', () {
    test('cria "Conversa 2", seleciona e grava uma vez', () async {
      final c = await setup();

      await ctl(c).newConversation();

      expect(st(c).conversations.map((e) => e.title),
          ['Conversa 1', 'Conversa 2']);
      expect(st(c).index, 1);
      expect(chats.saves, hasLength(1));
      // A conversa 1 vazia entra no snapshot (nao se perde ao reabrir).
      expect(chats.saves.single.all, hasLength(2));
    });

    test('select troca a conversa atual', () async {
      final c = await setup();
      await ctl(c).newConversation();

      ctl(c).select(0);

      expect(st(c).current.id, 'conv-1');
    });
  });

  test(
      'caracterizacao: LegacyChatStore real grava a mesma chave e o mesmo JSON '
      '(1 mensagem e nova conversa)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final real = await makeContainer(user: testUser(), overrides: [
      prefsProvider.overrideWithValue(prefs),
      oracleServiceProvider.overrideWithValue(oracle),
      analyticsServiceProvider.overrideWithValue(analytics),
    ]);
    addTearDown(real.dispose);
    real.listen(chatControllerProvider, (_, __) {});
    await real.read(chatControllerProvider.notifier).hydrate();
    final id = st(real).current.id;

    await ctl(real).send('Oi');

    expect(prefs.getKeys(), {'astrum.chat.u1'});
    expect(
        prefs.getString('astrum.chat.u1'),
        '{"conversations":[{"id":"$id","title":"Oi","messages":['
        '{"role":"user","text":"Oi"},'
        '{"role":"model","text":"resposta do oraculo"}]}]}');

    await ctl(real).newConversation();

    final json = jsonDecode(prefs.getString('astrum.chat.u1')!) as Map;
    final list = json['conversations'] as List;
    expect(list, hasLength(2));
    expect((list[0] as Map)['id'], id);
    expect((list[1] as Map)['title'], 'Conversa 2');
    expect((list[1] as Map)['messages'], isEmpty);
  });

  test('descartado durante a resposta: nao lanca e nao faz a 2a gravacao',
      () async {
    final gate = Completer<String>();
    oracle.completer = gate;
    final c = await makeContainer(user: testUser(), overrides: [
      chatRepositoryProvider.overrideWithValue(chats),
      oracleServiceProvider.overrideWithValue(oracle),
      analyticsServiceProvider.overrideWithValue(analytics),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(chatControllerProvider, (_, __) {});
    await c.read(chatControllerProvider.notifier).hydrate();
    final future = c.read(chatControllerProvider.notifier).send('Oi');
    await Future<void>.delayed(Duration.zero);

    sub.close();
    await c.pump();
    gate.complete('tarde');
    await future;

    expect(chats.saves, hasLength(1));
  });

  group('comportamento corrigido (defeitos do chat)', () {
    const erro = 'Não foi possível obter a resposta. Tente novamente.';

    test('(1) se o oraculo lanca, loading e liberado e ha resposta de erro',
        () async {
      oracle.failWith = StateError('oraculo fora');
      final c = await setup();

      await ctl(c).send('Oi');

      expect(st(c).loading, isFalse);
      expect(st(c).current.messages.map((m) => (m.role, m.text)),
          [('user', 'Oi'), ('model', erro)]);
      // Novo envio volta a funcionar.
      oracle.failWith = null;
      await ctl(c).send('Outra');
      expect(oracle.calls, hasLength(2));
      expect(st(c).current.messages.last.text, 'resposta do oraculo');
    });

    test('(1) se o save lanca, loading e liberado e ha resposta de erro',
        () async {
      chats.saveError = StateError('prefs fora');
      final c = await setup();

      await ctl(c).send('Oi');

      expect(st(c).loading, isFalse);
      expect(st(c).current.messages.last.text, erro);
      expect(oracle.calls, isEmpty);
    });

    test(
        '(2) trocar de conversa durante a resposta grava a resposta na '
        'conversa que originou o envio', () async {
      final gate = Completer<String>();
      oracle.completer = gate;
      final c = await setup();
      await ctl(c).newConversation(); // indice 1 = "Conversa 2"
      ctl(c).select(0);

      final future = ctl(c).send('Pergunta na conversa 1');
      await Future<void>.delayed(Duration.zero);
      ctl(c).select(1); // o usuario troca antes da resposta
      gate.complete('resposta');
      await future;

      final conv1 = st(c).conversations[0];
      final conv2 = st(c).conversations[1];
      expect(conv1.messages.map((m) => (m.role, m.text)),
          [('user', 'Pergunta na conversa 1'), ('model', 'resposta')]);
      expect(conv2.messages, isEmpty);
      expect(st(c).index, 1); // conversa ativa continua a escolhida
      expect(st(c).loading, isFalse);
    });

    test(
        '(1) se a 2a gravacao (da resposta) falha, a resposta fica na tela e '
        'loading e liberado', () async {
      chats = _FailSecondSave();
      final c = await setup();

      await ctl(c).send('Oi');

      expect(st(c).loading, isFalse);
      expect(st(c).current.messages.map((m) => (m.role, m.text)),
          [('user', 'Oi'), ('model', 'resposta do oraculo')]);
      expect(chats.saves, hasLength(2));
    });

    test('(3) enviar antes da hidratacao e ignorado (sem RangeError)',
        () async {
      final c = await setup(hydrate: false);

      await ctl(c).send('Oi');

      expect(oracle.calls, isEmpty);
      expect(chats.saves, isEmpty);
      expect(st(c).loading, isFalse);
    });
  });
}

/// Repositorio que aceita a 1a gravacao (mensagem do usuario) e falha a 2a
/// (resposta do oraculo).
class _FailSecondSave extends FakeChatRepository {
  @override
  Future<void> save(String uid, List<ChatConversation> all) async {
    if (saves.isNotEmpty) {
      saves.add((uid: uid, all: List.of(all)));
      throw StateError('prefs fora na 2a gravacao');
    }
    return super.save(uid, all);
  }
}
