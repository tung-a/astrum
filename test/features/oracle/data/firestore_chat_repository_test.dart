// O fake_cloud_firestore NAO aplica firestore.rules; as regras do chat sao
// cobertas por test_rules/ (emulador). Aqui so o comportamento do repositorio.
import 'dart:async';

import 'package:astrum/features/oracle/data/chat_repository.dart';
import 'package:astrum/features/oracle/data/firestore_chat_repository.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_chat_repository.dart';

/// Repositorio que registra as leituras "do servidor" e simula offline.
class _ServerReadRepo extends FirestoreChatRepository {
  _ServerReadRepo(this.db) : super(db);
  final FakeFirebaseFirestore db;
  bool offline = false;
  int serverReads = 0;
  final events = <String>[];

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> getServerPage(
      Query<Map<String, dynamic>> query) async {
    if (offline) throw const ChatOfflineException();
    serverReads++;
    final r = await query.get();
    events.add('read:${r.docs.length}');
    return r;
  }
}

/// Commit de exclusao que nunca completa (offline) e prazo curto.
class _HangDeleteRepo extends FirestoreChatRepository {
  _HangDeleteRepo(super.db)
      : super(deleteCommitTimeout: const Duration(milliseconds: 50));
  bool hang = true;

  @override
  Future<void> commitDelete(WriteBatch batch) =>
      hang ? Completer<void>().future : super.commitDelete(batch);
}

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreChatRepository repo;
  final t0 = DateTime.utc(2026, 11, 14, 12);

  ChatTurnStored m(int i, String text, {String role = 'user'}) =>
      ChatTurnStored(
        id: 'm${i.toString().padLeft(4, '0')}',
        role: role,
        text: text,
        createdAt: t0.add(Duration(milliseconds: i)),
      );

  Future<void> send(String convId, int i, String text,
      {bool isNew = false, String? title, DateTime? at}) {
    final msg = m(i, text);
    return repo.appendMessage('u1',
        convId: convId,
        message: msg,
        updatedAt: at ?? msg.createdAt!,
        isNew: isNew,
        title: title);
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreChatRepository(db);
  });

  test('e um ChatRepository e gera ids unicos', () {
    expect(repo, isA<ChatRepository>());
    expect(repo.newId(), isNot(repo.newId()));
  });

  test('1a mensagem cria a conversa com contador 1, titulo e schemaVersion',
      () async {
    await send('c1', 1, 'Qual meu signo?', isNew: true);
    final c = (await db.doc('users/u1/conversations/c1').get()).data()!;
    expect(c['messageCount'], 1);
    expect(c['title'], 'Qual meu signo?');
    expect(c['schemaVersion'], 1);
    expect(c['createdAt'], isA<Timestamp>());
    final msg = (await db.doc('users/u1/conversations/c1/messages/m0001').get())
        .data()!;
    expect(msg['role'], 'user');
    expect(msg['text'], 'Qual meu signo?');
  });

  test('titulo explicito e cortado em 80 sem partir emoji', () async {
    await send('c1', 1, 'x', isNew: true, title: '${'a' * 79}\u{1F52E}');
    final c = (await db.doc('users/u1/conversations/c1').get()).data()!;
    expect(c['title'], 'a' * 79);
  });

  test('mensagens seguintes incrementam o contador e nao mudam o titulo',
      () async {
    await send('c1', 1, 'primeira', isNew: true);
    await send('c1', 2, 'segunda', title: 'IGNORADO');
    await send('c1', 3, 'terceira');
    final c = (await db.doc('users/u1/conversations/c1').get()).data()!;
    expect(c['messageCount'], 3);
    expect(c['title'], 'primeira');
    expect(await repo.remoteMessageCount('u1', 'c1'), 3);
  });

  test('remoteMessageCount: conversa inexistente = null', () async {
    expect(await repo.remoteMessageCount('u1', 'nada'), isNull);
  });

  test('texto acima de 10000 e truncado; role invalido vira user', () async {
    await send('c1', 1, 'a' * 10050, isNew: true);
    await repo.appendMessage('u1',
        convId: 'c1',
        message: ChatTurnStored(
            id: 'm0002', role: 'system', text: 'x', createdAt: t0),
        updatedAt: t0);
    final a = await db.doc('users/u1/conversations/c1/messages/m0001').get();
    expect((a.data()!['text'] as String).length, 10000);
    final b = await db.doc('users/u1/conversations/c1/messages/m0002').get();
    expect(b.data()!['role'], 'user');
  });

  test('exige id e createdAt; recusa mensagem vazia', () {
    expect(
        () => repo.appendMessage('u1',
            convId: 'c',
            message: const ChatTurnStored(role: 'user', text: 'x'),
            updatedAt: t0),
        throwsArgumentError);
    expect(
        () => repo.appendMessage('u1',
            convId: 'c', message: m(1, ''), updatedAt: t0, isNew: true),
        throwsArgumentError);
  });

  test('watchConversations: mais recente primeiro, so metadados, limite 50',
      () async {
    for (var i = 0; i < 55; i++) {
      await send('c$i', 1, 'conversa $i',
          isNew: true, at: t0.add(Duration(minutes: i)));
    }
    final list = await repo.watchConversations('u1').first;
    expect(list, hasLength(50));
    expect(list.first.id, 'c54');
    expect(list.last.id, 'c5');
    expect(list.first.messages, isEmpty);
    expect(list.first.messageCount, 1);
    expect(list.first.updatedAt, isNotNull);
  });

  test('watchConversations: enviar mensagem move a conversa para o topo',
      () async {
    await send('a', 1, 'a', isNew: true, at: t0);
    await send('b', 1, 'b',
        isNew: true, at: t0.add(const Duration(minutes: 1)));
    await send('a', 2, 'a2', at: t0.add(const Duration(minutes: 2)));
    final list = await repo.watchConversations('u1').first;
    expect(list.map((c) => c.id), ['a', 'b']);
    expect(list.first.messageCount, 2);
  });

  test('watchMessages: ordem cronologica, so da conversa e do uid', () async {
    await send('c1', 1, 'um', isNew: true);
    await send('c1', 2, 'dois');
    await send('c1', 3, 'tres');
    await send('c2', 1, 'outra', isNew: true);
    final msgs = await repo.watchMessages('u1', 'c1').first;
    expect(msgs.map((x) => x.text), ['um', 'dois', 'tres']);
    expect(msgs.first.id, 'm0001');
    expect(msgs.first.createdAt, isNotNull);
    expect(await repo.watchMessages('u2', 'c1').first, isEmpty);
  });

  test('watchMessages: limit devolve as ultimas, em ordem cronologica',
      () async {
    await send('c1', 1, 'um', isNew: true);
    for (var i = 2; i <= 5; i++) {
      await send('c1', i, 'msg$i');
    }
    final msgs = await repo.watchMessages('u1', 'c1', limit: 2).first;
    expect(msgs.map((x) => x.text), ['msg4', 'msg5']);
  });

  test('deleteConversation apaga mensagens (mais de 400) e a conversa',
      () async {
    await send('c1', 1, 'um', isNew: true);
    await send('keep', 1, 'fica', isNew: true);
    final batch = db.batch();
    for (var i = 2; i <= 450; i++) {
      final id = 'm${i.toString().padLeft(4, '0')}';
      batch.set(db.doc('users/u1/conversations/c1/messages/$id'),
          {'role': 'user', 'text': 'x', 'createdAt': Timestamp.now()});
    }
    await batch.commit();
    await repo.deleteConversation('u1', 'c1');
    expect(await repo.remoteMessageCount('u1', 'c1'), isNull);
    expect(
        (await db.collection('users/u1/conversations/c1/messages').get()).docs,
        isEmpty);
    expect(await repo.remoteMessageCount('u1', 'keep'), 1);
  });

  test('deleteAllConversations pagina (60 conversas) e preserva outro uid',
      () async {
    for (var i = 0; i < 60; i++) {
      await send('c$i', 1, 'x$i', isNew: true);
    }
    await repo.appendMessage('u2',
        convId: 'o', message: m(1, 'outro'), updatedAt: t0, isNew: true);
    final ids = await repo.deleteAllConversations('u1');
    expect(ids.toSet(), {for (var i = 0; i < 60; i++) 'c$i'});
    expect((await db.collection('users/u1/conversations').get()).docs, isEmpty);
    expect(await repo.remoteMessageCount('u2', 'o'), 1);
  });

  group('exclusao le do servidor', () {
    late _ServerReadRepo srv;
    setUp(() => srv = _ServerReadRepo(db));

    Future<void> seed(String conv, int n) async {
      final batch = db.batch();
      batch.set(db.doc('users/u1/conversations/$conv'), {
        'title': 't',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'messageCount': n,
        'schemaVersion': 1,
      });
      for (var i = 1; i <= n; i++) {
        batch.set(db.doc('users/u1/conversations/$conv/messages/m$i'),
            {'role': 'user', 'text': 'x', 'createdAt': Timestamp.now()});
      }
      await batch.commit();
    }

    test('offline: falha com erro claro e nao apaga nada', () async {
      await seed('c1', 3);
      srv.offline = true;
      await expectLater(srv.deleteConversation('u1', 'c1'),
          throwsA(isA<ChatOfflineException>()));
      await expectLater(srv.deleteAllConversations('u1'),
          throwsA(isA<ChatOfflineException>()));
      expect(
          (await db.collection('users/u1/conversations/c1/messages').get())
              .docs,
          hasLength(3));
      expect((await db.doc('users/u1/conversations/c1').get()).exists, isTrue);
    });

    test(
        'commit de exclusao que nao completa: ChatOfflineException e retomavel',
        () async {
      await seed('c1', 3);
      final h = _HangDeleteRepo(db);
      await expectLater(h.deleteConversation('u1', 'c1'),
          throwsA(isA<ChatOfflineException>()));
      expect((await db.doc('users/u1/conversations/c1').get()).exists, isTrue);
      h.hang = false; // nova tentativa idempotente
      await h.deleteConversation('u1', 'c1');
      expect((await db.doc('users/u1/conversations/c1').get()).exists, isFalse);
      expect(
          (await db.collection('users/u1/conversations/c1/messages').get())
              .docs,
          isEmpty);
    });

    test('so apaga a conversa depois de pagina vazia lida do servidor',
        () async {
      await seed('c1', 450);
      await srv.deleteConversation('u1', 'c1');
      // 450 mensagens: paginas de 400, 50 e uma vazia (confirmacao).
      expect(srv.events, ['read:400', 'read:50', 'read:0']);
      expect((await db.doc('users/u1/conversations/c1').get()).exists, isFalse);
      expect(
          (await db.collection('users/u1/conversations/c1/messages').get())
              .docs,
          isEmpty);
    });

    test('idempotente: conversa inexistente nao falha', () async {
      await srv.deleteConversation('u1', 'nada');
      await srv.deleteConversation('u1', 'nada');
      expect(srv.events, ['read:0', 'read:0']);
    });

    test('deleteAll le todas as paginas do servidor e termina vazio', () async {
      for (var i = 0; i < 55; i++) {
        await seed('c$i', 1);
      }
      await srv.deleteAllConversations('u1');
      expect(
          (await db.collection('users/u1/conversations').get()).docs, isEmpty);
      expect(srv.events.last, 'read:0');
      expect(srv.serverReads, greaterThan(55));
    });
  });

  group('InMemoryChatRepository (fake de teste)', () {
    test('mesmo contrato basico: cria, incrementa, ordena e apaga', () async {
      final mem = InMemoryChatRepository();
      await mem.appendMessage('u',
          convId: 'a', message: m(1, 'um'), updatedAt: t0, isNew: true);
      await mem.appendMessage('u',
          convId: 'b',
          message: m(1, 'b'),
          updatedAt: t0.add(const Duration(seconds: 1)),
          isNew: true);
      await mem.appendMessage('u',
          convId: 'a',
          message: m(2, 'dois'),
          updatedAt: t0.add(const Duration(seconds: 2)));
      final list = await mem.watchConversations('u').first;
      expect(list.map((c) => c.id), ['a', 'b']);
      expect(list.first.messageCount, 2);
      expect((await mem.watchMessages('u', 'a').first).map((x) => x.text),
          ['um', 'dois']);
      await mem.deleteConversation('u', 'a');
      expect(await mem.remoteMessageCount('u', 'a'), isNull);
    });
  });
}
