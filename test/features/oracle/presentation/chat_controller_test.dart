import 'dart:async';

import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:astrum/features/oracle/presentation/chat_controller.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/in_memory_chat_repository.dart';
import '../../../support/make_container.dart';

/// Repositorio que registra as gravacoes e pode falhar sob comando.
class _SpyRepo extends InMemoryChatRepository {
  final appends = <({String uid, String convId, String role, bool isNew})>[];
  Object? appendError;

  @override
  Future<void> appendMessage(
    String uid, {
    required String convId,
    required ChatTurnStored message,
    required DateTime updatedAt,
    String? title,
    bool isNew = false,
  }) {
    appends.add((uid: uid, convId: convId, role: message.role, isNew: isNew));
    if (appendError != null) return Future.error(appendError!);
    return super.appendMessage(uid,
        convId: convId,
        message: message,
        updatedAt: updatedAt,
        title: title,
        isNew: isNew);
  }
}

/// Falha a lista de conversas enquanto [failList] for true.
class _FlakyListRepo extends _SpyRepo {
  bool failList = true;

  @override
  Stream<List<ChatConversation>> watchConversations(String uid) => failList
      ? Stream<List<ChatConversation>>.error(StateError('unavailable'))
      : super.watchConversations(uid);
}

/// So emite o 1o snapshot da lista: o rascunho nunca e confirmado pela nuvem.
class _StaleListRepo extends _SpyRepo {
  @override
  Stream<List<ChatConversation>> watchConversations(String uid) =>
      super.watchConversations(uid).take(1);
}

void main() {
  late _SpyRepo repo;
  late FakeOracleService oracle;
  late FakeAnalytics analytics;
  final uidSource = StateProvider<String?>((ref) => 'u1');

  setUp(() {
    repo = _SpyRepo();
    oracle = FakeOracleService(reply: 'resposta do oraculo');
    analytics = FakeAnalytics();
  });

  Future<ProviderContainer> setup({
    bool loggedIn = true,
    bool hydrate = true,
    bool switchable = false,
  }) async {
    final c = await makeContainer(
      user: loggedIn ? testUser() : null,
      overrides: [
        if (switchable)
          currentUidProvider.overrideWith((ref) => ref.watch(uidSource)),
        chatRepositoryProvider.overrideWithValue(repo),
        oracleServiceProvider.overrideWithValue(oracle),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
    );
    addTearDown(c.dispose);
    c.listen(chatControllerProvider, (_, __) {}); // mantem o autoDispose vivo
    if (hydrate) {
      await c.read(chatControllerProvider.notifier).hydrate();
      await pumpEventQueue();
    }
    return c;
  }

  ChatController ctl(ProviderContainer c) =>
      c.read(chatControllerProvider.notifier);
  ChatState st(ProviderContainer c) => c.read(chatControllerProvider);

  Future<void> seed(String uid, String convId, int n,
      {String? title, DateTime? at}) async {
    final base = at ?? DateTime(2026, 1, 1);
    for (var i = 0; i < n; i++) {
      await repo.appendMessage(uid,
          convId: convId,
          message: ChatTurnStored(
              id: 'm$i',
              role: i.isEven ? 'user' : 'model',
              text: 'texto $i',
              createdAt: base.add(Duration(seconds: i))),
          updatedAt: base.add(Duration(seconds: i)),
          title: title,
          isNew: i == 0);
    }
  }

  group('hydrate', () {
    test('sem conversas: rascunho "Conversa 1", nada gravado, idempotente',
        () async {
      final c = await setup(hydrate: false);
      expect(st(c).hydrated, isFalse);
      expect(st(c).current.id, 'x'); // placeholder antes de hidratar

      await ctl(c).hydrate();
      await ctl(c).hydrate();
      await pumpEventQueue();

      expect(st(c).hydrated, isTrue);
      expect(st(c).conversations.map((e) => e.title), ['Conversa 1']);
      expect(repo.appends, isEmpty);
    });

    test('abre na conversa mais recente; lista da mais recente para a antiga',
        () async {
      await seed('u1', 'velha', 2, title: 'Velha', at: DateTime(2026, 1, 1));
      await seed('u1', 'nova', 2, title: 'Nova', at: DateTime(2026, 2, 1));
      final c = await setup();

      expect(st(c).conversations.map((e) => e.id), ['nova', 'velha']);
      expect(st(c).current.id, 'nova');
      expect(st(c).current.messages.map((m) => m.text), ['texto 0', 'texto 1']);
    });

    test('sem usuario nao assina nada', () async {
      final c = await setup(loggedIn: false);
      await ctl(c).hydrate();

      expect(st(c).hydrated, isFalse);
    });

    test('reabrir a tela (novo controller) recarrega o historico', () async {
      final c1 = await setup();
      await ctl(c1).send('Oi');
      await pumpEventQueue();
      c1.dispose();

      final c2 = await setup();

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

  group('falha ao carregar o historico', () {
    test('error ate tentar de novo; retry hidrata e limpa o erro', () async {
      final flaky = _FlakyListRepo();
      repo = flaky;
      final c = await setup();

      expect(st(c).error, isTrue);
      expect(st(c).hydrated, isFalse);

      flaky.failList = false;
      await ctl(c).retry();
      await pumpEventQueue();

      expect(st(c).error, isFalse);
      expect(st(c).hydrated, isTrue);
      expect(st(c).conversations, hasLength(1));
    });
  });

  group('send', () {
    test('devolve se o envio foi aceito e so chama onAccepted ao aceitar',
        () async {
      final c = await setup();
      var accepted = 0;

      expect(await ctl(c).send('  ', onAccepted: () => accepted++), isFalse);
      expect(
          await ctl(c)
              .send('Oi', expectedUid: 'outro', onAccepted: () => accepted++),
          isFalse);
      expect(accepted, 0);
      expect(oracle.calls, isEmpty);

      expect(
          await ctl(c)
              .send('Oi', expectedUid: 'u1', onAccepted: () => accepted++),
          isTrue);
      expect(accepted, 1);
    });

    test('recusado antes da hidratacao e com resposta em andamento', () async {
      final cold = await setup(hydrate: false);
      var accepted = 0;
      expect(await ctl(cold).send('Oi', onAccepted: () => accepted++), isFalse);
      expect(accepted, 0);

      final gate = Completer<String>();
      oracle.completer = gate;
      final c = await setup();
      final first = ctl(c).send('Primeira');
      await Future<void>.delayed(Duration.zero);
      expect(
          await ctl(c).send('Segunda', onAccepted: () => accepted++), isFalse);
      expect(accepted, 0);
      gate.complete('ok');
      expect(await first, isTrue);
    });

    test('duas mensagens rapidas: so a 1a cria a conversa (isNew)', () async {
      repo = _StaleListRepo();
      final c = await setup();

      await ctl(c).send('Primeira');
      await ctl(c).send('Segunda');
      await pumpEventQueue();

      expect(repo.appends.where((a) => a.isNew), hasLength(1));
      expect(repo.appends, hasLength(4));
      expect(await repo.remoteMessageCount('u1', st(c).current.id), 4);
    });

    test('texto vazio ou so espacos e ignorado', () async {
      final c = await setup();

      await ctl(c).send('');
      await ctl(c).send('   ');

      expect(repo.appends, isEmpty);
      expect(oracle.calls, isEmpty);
      expect(st(c).loading, isFalse);
    });

    test('1a mensagem cria a conversa (titulo), grava 2 mensagens e conta',
        () async {
      final c = await setup();

      await ctl(c).send('  Qual a energia de hoje?  ');
      await pumpEventQueue();

      final conv = st(c).current;
      expect(conv.title, 'Qual a energia de hoje?');
      expect(conv.messages.map((m) => (m.role, m.text)), [
        ('user', 'Qual a energia de hoje?'),
        ('model', 'resposta do oraculo'),
      ]);
      expect(oracle.calls.single.prompt, 'Qual a energia de hoje?');
      expect(analytics.events, ['send_message_chat']);
      expect(st(c).loading, isFalse);
      expect(repo.appends.map((a) => (a.role, a.isNew)),
          [('user', true), ('model', false)]);
      expect(await repo.remoteMessageCount('u1', conv.id), 2);
    });

    test('2a mensagem mantem o titulo e a conversa', () async {
      final c = await setup();

      await ctl(c).send('Primeira');
      await ctl(c).send('Segunda');
      await pumpEventQueue();

      expect(st(c).conversations, hasLength(1));
      expect(st(c).current.title, 'Primeira');
      expect(st(c).current.messages, hasLength(4));
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
      await pumpEventQueue();

      expect(oracle.calls, hasLength(1));
      expect(st(c).current.messages, hasLength(2));
    });

    test('createdAt e estritamente crescente mesmo com relogio parado',
        () async {
      final c = await setup(); // relogio fixo do makeContainer
      await ctl(c).send('Oi');
      await pumpEventQueue();

      final msgs = st(c).current.messages;
      expect(msgs[1].createdAt!.isAfter(msgs[0].createdAt!), isTrue);
    });

    test('se o oraculo lanca, loading e liberado e ha resposta de erro',
        () async {
      oracle.failWith = StateError('oraculo fora');
      final c = await setup();

      await ctl(c).send('Oi');
      await pumpEventQueue();

      expect(st(c).loading, isFalse);
      expect(st(c).current.messages.map((m) => (m.role, m.text)), [
        ('user', 'Oi'),
        ('model', 'Não foi possível obter a resposta. Tente novamente.')
      ]);
      oracle.failWith = null;
      await ctl(c).send('Outra');
      expect(oracle.calls, hasLength(2));
    });

    test('falha de gravacao nao trava loading nem vaza o texto no log',
        () async {
      repo.appendError = StateError('permission-denied');
      final logs = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = old);
      final c = await setup();

      await ctl(c).send('segredo de amor');
      await pumpEventQueue();

      expect(st(c).loading, isFalse);
      expect(repo.appends, hasLength(2));
      expect(logs, isNotEmpty);
      expect(logs.join(), isNot(contains('segredo')));
    });

    test('enviar antes da hidratacao e ignorado', () async {
      final c = await setup(hydrate: false);

      await ctl(c).send('Oi');

      expect(oracle.calls, isEmpty);
      expect(repo.appends, isEmpty);
      expect(st(c).loading, isFalse);
    });

    test('mensagem acima de 10000 caracteres e truncada', () async {
      final c = await setup();

      await ctl(c).send('a' * 10050);
      await pumpEventQueue();

      expect(st(c).current.messages.first.text.length, 10000);
      expect(oracle.calls.single.prompt.length, 10000);
    });
  });

  group('newConversation e select', () {
    test('rascunho nao grava; o documento nasce na 1a mensagem', () async {
      await seed('u1', 'a', 2, title: 'Antiga');
      final c = await setup();
      final before = repo.appends.length;

      await ctl(c).newConversation();

      expect(st(c).conversations.map((e) => e.title), ['Conversa 2', 'Antiga']);
      expect(st(c).index, 0);
      expect(repo.appends.length, before);
      expect(await repo.remoteMessageCount('u1', st(c).current.id), isNull);

      await ctl(c).send('Nova pergunta');
      await pumpEventQueue();

      expect(st(c).conversations, hasLength(2)); // rascunho virou conversa
      expect(st(c).conversations.first.title, 'Nova pergunta');
      expect(await repo.remoteMessageCount('u1', st(c).current.id), 2);
    });

    test('newConversation repetida reaproveita o rascunho vazio', () async {
      final c = await setup();
      final id = st(c).current.id;

      await ctl(c).newConversation();
      await ctl(c).newConversation();

      expect(st(c).conversations, hasLength(1));
      expect(st(c).current.id, id);
    });

    test('select troca a conversa e carrega as mensagens dela', () async {
      await seed('u1', 'a', 2, title: 'A', at: DateTime(2026, 1, 1));
      await seed('u1', 'b', 4, title: 'B', at: DateTime(2026, 2, 1));
      final c = await setup();
      expect(st(c).current.id, 'b');

      ctl(c).select(1);
      await pumpEventQueue();

      expect(st(c).current.id, 'a');
      expect(st(c).current.messages, hasLength(2));
    });

    test('a resposta vai para a conversa que originou o envio', () async {
      await seed('u1', 'a', 2, title: 'A', at: DateTime(2026, 1, 1));
      await seed('u1', 'b', 2, title: 'B', at: DateTime(2026, 2, 1));
      final gate = Completer<String>();
      oracle.completer = gate;
      final c = await setup(); // abre em 'b'

      final future = ctl(c).send('Pergunta em B');
      await Future<void>.delayed(Duration.zero);
      ctl(c).select(1); // 'a'
      gate.complete('resposta');
      await future;
      await pumpEventQueue();

      expect(await repo.remoteMessageCount('u1', 'b'), 4);
      expect(await repo.remoteMessageCount('u1', 'a'), 2);
      expect(st(c).loading, isFalse);
      expect(st(c).current.id, 'a');
    });
  });

  group('sincronizacao e usuario', () {
    test('conversa excluida em outro aparelho: resposta e descartada',
        () async {
      await seed('u1', 'a', 2, title: 'A');
      repo.appends.clear();
      final gate = Completer<String>();
      oracle.completer = gate;
      final c = await setup();

      final future = ctl(c).send('Oi');
      await Future<void>.delayed(Duration.zero);
      await repo.deleteConversation('u1', 'a'); // outro aparelho
      await pumpEventQueue();
      gate.complete('resposta');
      await future;

      expect(repo.appends.where((a) => a.role == 'model'), isEmpty);
      expect(st(c).loading, isFalse);
    });

    test('mensagens de outro aparelho aparecem pelos listeners', () async {
      await seed('u1', 'a', 2, title: 'A');
      final c = await setup();

      await repo.appendMessage('u1',
          convId: 'a',
          message: ChatTurnStored(
              id: 'x',
              role: 'user',
              text: 'do outro aparelho',
              createdAt: DateTime(2026, 3, 1)),
          updatedAt: DateTime(2026, 3, 1));
      await pumpEventQueue();

      expect(st(c).current.messages.last.text, 'do outro aparelho');
    });

    test('troca de uid reinicia o estado e ignora resposta pendente do antigo',
        () async {
      await seed('u2', 'b', 2, title: 'Do u2');
      repo.appends.clear();
      final gate = Completer<String>();
      oracle.completer = gate;
      final c = await setup(switchable: true);

      final future = ctl(c).send('Oi do u1');
      await Future<void>.delayed(Duration.zero);
      c.read(uidSource.notifier).state = 'u2';
      await pumpEventQueue();
      expect(st(c).hydrated, isFalse);
      expect(st(c).loading, isFalse);
      await ctl(c).hydrate();
      await pumpEventQueue();
      expect(st(c).conversations.map((e) => e.id), ['b']);

      gate.complete('resposta tardia');
      await future;
      await pumpEventQueue();

      // So a mensagem do usuario do u1 foi gravada; nada novo no u2.
      expect(repo.appends.where((a) => a.uid == 'u2'), isEmpty);
      expect(repo.appends.where((a) => a.role == 'model'), isEmpty);
      expect(await repo.remoteMessageCount('u2', 'b'), 2);
      expect(st(c).current.messages, hasLength(2));
    });

    test('logout limpa o estado', () async {
      await seed('u1', 'a', 2, title: 'A');
      final c = await setup(switchable: true);
      expect(st(c).hydrated, isTrue);

      c.read(uidSource.notifier).state = null;
      await pumpEventQueue();
      await ctl(c).hydrate();

      expect(st(c).hydrated, isFalse);
      expect(st(c).conversations, isEmpty);
    });
  });

  group('limite de 500 mensagens', () {
    test('com 500 mensagens mostra o aviso e nao envia', () async {
      await seed('u1', 'a', 500, title: 'Cheia');
      final c = await setup();

      expect(st(c).current.messages, hasLength(501));
      expect(st(c).current.messages.last.text,
          'Esta conversa atingiu o limite. Inicie uma nova conversa.');
      expect(st(c).limitReached, isTrue);

      expect(await ctl(c).send('Mais uma'), isFalse);

      expect(oracle.calls, isEmpty);
      expect(repo.appends, hasLength(500)); // so as do seed
      expect(await repo.remoteMessageCount('u1', 'a'), 500);
    });

    test('com 498 ainda cabe pergunta e resposta', () async {
      await seed('u1', 'a', 498, title: 'Quase');
      final c = await setup();
      expect(st(c).limitReached, isFalse);

      await ctl(c).send('Cabe');
      await pumpEventQueue();

      expect(await repo.remoteMessageCount('u1', 'a'), 500);
      expect(st(c).limitReached, isTrue);
    });

    test('nova conversa permite continuar depois do limite', () async {
      await seed('u1', 'a', 500, title: 'Cheia');
      final c = await setup();

      await ctl(c).newConversation();
      await ctl(c).send('Recomecar');
      await pumpEventQueue();

      expect(st(c).current.messages.map((m) => m.text),
          ['Recomecar', 'resposta do oraculo']);
    });
  });
}
