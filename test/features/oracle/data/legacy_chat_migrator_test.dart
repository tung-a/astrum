import 'dart:async';
import 'dart:convert';

import 'package:astrum/features/oracle/data/firestore_chat_repository.dart';
import 'package:astrum/features/oracle/data/legacy_chat_migrator.dart';
import 'package:astrum/features/oracle/data/legacy_chat_store.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FirebaseException _err(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

/// Repositorio que imita as regras do servidor (o fake nao as aplica) e
/// serializa as escritas (como o servidor): mensagem existente, conversa
/// nova sobre existente e atualizacao de conversa inexistente sao negadas.
/// Tambem conta as escritas aceitas e permite falhar a N-esima.
class _RulesRepo extends FirestoreChatRepository {
  _RulesRepo(this.db) : super(db);
  final FakeFirebaseFirestore db;
  Future<void> _tail = Future.value();
  int accepted = 0;
  int? failOnAccepted; // lanca 'unavailable' ao tentar a escrita de numero N+1
  bool hang = false; // grava, mas o Future nunca completa (offline)
  int? serverCountOverride; // resposta de fromServer
  Object? syncError;
  bool syncHangs = false;

  @override
  Future<void> appendMessage(
    String uid, {
    required String convId,
    required ChatTurnStored message,
    required DateTime updatedAt,
    String? title,
    bool isNew = false,
  }) {
    final done = Completer<void>();
    _tail = _tail.then((_) async {
      try {
        final conv = await db.doc('users/$uid/conversations/$convId').get();
        final msg = await db
            .doc('users/$uid/conversations/$convId/messages/${message.id}')
            .get();
        if (failOnAccepted != null && accepted >= failOnAccepted!) {
          throw _err('unavailable');
        }
        if (msg.exists || (isNew && conv.exists)) {
          throw _err('permission-denied');
        }
        if (!isNew && !conv.exists) throw _err('not-found');
        await super.appendMessage(uid,
            convId: convId,
            message: message,
            updatedAt: updatedAt,
            title: title,
            isNew: isNew);
        accepted++;
        if (!hang) done.complete();
      } catch (e) {
        done.completeError(e);
      }
    });
    return done.future;
  }

  @override
  Future<int?> remoteMessageCount(String uid, String convId,
      {bool fromServer = false}) async {
    if (fromServer && serverCountOverride != null) return serverCountOverride;
    return super.remoteMessageCount(uid, convId, fromServer: fromServer);
  }

  @override
  Future<void> waitForSync() async {
    if (syncError != null) throw syncError!;
    if (syncHangs) return Completer<void>().future;
  }
}

String _legacy(List<List<(String, String)>> convs, {List<String>? ids}) =>
    jsonEncode({
      'conversations': [
        for (var i = 0; i < convs.length; i++)
          {
            'id': ids?[i] ?? 'c$i',
            'title': 'Conversa ${i + 1}',
            'messages': [
              for (final (role, text) in convs[i]) {'role': role, 'text': text},
            ],
          },
      ],
    });

void main() {
  late SharedPreferences prefs;
  late LegacyChatStore store;
  late FakeFirebaseFirestore db;
  late _RulesRepo repo;
  final now = DateTime.utc(2026, 11, 14, 12);

  LegacyChatMigrator migrator({
    LegacyChatStore? s,
    _RulesRepo? r,
    Duration timeout = const Duration(milliseconds: 200),
  }) =>
      LegacyChatMigrator(
          legacy: s ?? store,
          repository: r ?? repo,
          now: () => now,
          syncTimeout: timeout);

  Future<List<Map<String, dynamic>>> messages(String uid, String conv) async {
    final q = await db
        .collection('users/$uid/conversations/$conv/messages')
        .orderBy('createdAt')
        .get();
    return [
      for (final d in q.docs) {'id': d.id, ...d.data()}
    ];
  }

  Future<int?> count(String uid, String conv) async =>
      (await db.doc('users/$uid/conversations/$conv').get())
          .data()?['messageCount'] as int?;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = LegacyChatStore(prefs);
    db = FakeFirebaseFirestore();
    repo = _RulesRepo(db);
  });

  final two = [
    [('user', 'oi'), ('model', 'ola'), ('user', 'tudo bem?')],
    [('user', 'segunda'), ('model', 'resposta')],
  ];

  test('flag presente: nao faz nada', () async {
    await prefs.setString('astrum.chat.migrated.u1', 'done');
    await prefs.setString('astrum.chat.u1', _legacy(two));
    expect(await migrator().run('u1'), MigrationResult.alreadyDone);
    expect(repo.accepted, 0);
    expect(prefs.getString('astrum.chat.u1'), isNotNull);
  });

  test('legado ausente: grava a flag e sai', () async {
    expect(await migrator().run('u1'), MigrationResult.nothingToMigrate);
    expect(prefs.getString('astrum.chat.migrated.u1'), isNotNull);
    expect(repo.accepted, 0);
  });

  test('lista vazia ou so rascunhos: flag, sem escrita', () async {
    await prefs.setString('astrum.chat.u1', jsonEncode({'conversations': []}));
    expect(await migrator().run('u1'), MigrationResult.nothingToMigrate);
    await prefs.setString('astrum.chat.u2', _legacy([[], []]));
    expect(await migrator().run('u2'), MigrationResult.nothingToMigrate);
    expect(prefs.getString('astrum.chat.migrated.u2'), isNotNull);
    expect(repo.accepted, 0);
  });

  test('JSON corrompido: nao apaga, copia para .bak, flag corrupt, sem laco',
      () async {
    const bad = '{"conversations": [ {"id": ';
    await prefs.setString('astrum.chat.u1', bad);
    expect(await migrator().run('u1'), MigrationResult.corrupt);
    expect(prefs.getString('astrum.chat.u1'), bad);
    expect(prefs.getString('astrum.chat.u1.bak'), bad);
    expect(prefs.getString('astrum.chat.migrated.u1'), 'corrupt');
    expect(repo.accepted, 0);
    expect(await migrator().run('u1'), MigrationResult.alreadyDone);
  });

  test('formato inesperado (id nulo, mensagem nao-mapa) tambem e corrompido',
      () async {
    const bad1 = '{"conversations":[{"id":null,"messages":[]}]}';
    await prefs.setString('astrum.chat.u1', bad1);
    expect(await migrator().run('u1'), MigrationResult.corrupt);
    const bad2 = '{"conversations":[{"id":"a","messages":[42]}]}';
    await prefs.setString('astrum.chat.u2', bad2);
    expect(await migrator().run('u2'), MigrationResult.corrupt);
    expect(prefs.getString('astrum.chat.u2'), bad2);
  });

  test('caminho feliz: envia tudo, confere, grava .bak, apaga o original',
      () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    expect(await migrator().run('u1'), MigrationResult.migrated);

    expect(await count('u1', 'c0'), 3);
    expect(await count('u1', 'c1'), 2);
    final m0 = await messages('u1', 'c0');
    expect(m0.map((m) => m['id']), ['m0001', 'm0002', 'm0003']);
    expect(m0.map((m) => m['text']), ['oi', 'ola', 'tudo bem?']);
    expect(m0.map((m) => m['role']), ['user', 'model', 'user']);
    final c0 = (await db.doc('users/u1/conversations/c0').get()).data()!;
    final c1 = (await db.doc('users/u1/conversations/c1').get()).data()!;
    expect(c0['title'], 'Conversa 1');
    expect(c0['schemaVersion'], 1);
    expect(
        (c1['updatedAt'] as Timestamp).toDate().isAtSameMomentAs(now), isTrue);
    expect((c0['updatedAt'] as Timestamp).compareTo(c1['updatedAt']), -1);

    expect(prefs.getString('astrum.chat.u1.bak'), raw);
    expect(prefs.getString('astrum.chat.u1'), isNull);
    expect(prefs.getString('astrum.chat.migrated.u1'), 'done');
  });

  test('reexecucao nao duplica nada', () async {
    await prefs.setString('astrum.chat.u1', _legacy(two));
    await migrator().run('u1');
    final accepted = repo.accepted;
    expect(await migrator().run('u1'), MigrationResult.alreadyDone);
    expect(repo.accepted, accepted);
    expect(await count('u1', 'c0'), 3);
  });

  test('reexecucao com flag perdida mas dados no servidor nao duplica',
      () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    await migrator().run('u1');
    final accepted = repo.accepted;
    await prefs.remove('astrum.chat.migrated.u1');
    await prefs.setString('astrum.chat.u1', raw); // legado volta
    expect(await migrator().run('u1'), MigrationResult.migrated);
    expect(repo.accepted, accepted); // nada reenviado
    expect(await count('u1', 'c0'), 3);
  });

  test('queda no meio: nada apagado; retoma pela contagem, sem duplicar',
      () async {
    final raw = _legacy(two); // 5 mensagens no total
    await prefs.setString('astrum.chat.u1', raw);
    repo.failOnAccepted = 2; // 3a escrita falha (conversa c0 fica com 2)
    expect(await migrator().run('u1'), MigrationResult.incomplete);
    expect(prefs.getString('astrum.chat.u1'), raw);
    expect(prefs.getString('astrum.chat.u1.bak'), isNull);
    expect(prefs.getString('astrum.chat.migrated.u1'), isNull);
    expect(await count('u1', 'c0'), 2);

    repo.failOnAccepted = null;
    final before = repo.accepted;
    expect(await migrator().run('u1'), MigrationResult.migrated);
    expect(repo.accepted - before, 3); // so o que faltava: 1 de c0 + 2 de c1
    expect(await count('u1', 'c0'), 3);
    expect(await count('u1', 'c1'), 2);
    expect((await messages('u1', 'c0')).map((m) => m['text']),
        ['oi', 'ola', 'tudo bem?']);
    expect(prefs.getString('astrum.chat.u1'), isNull);
  });

  test('dois aparelhos migrando o mesmo legado: sem duplicar', () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    final a = migrator();
    final b = migrator();
    final results = await Future.wait([a.run('u1'), b.run('u1')]);
    expect(results, everyElement(isNot(MigrationResult.incomplete)));
    expect(repo.accepted, 5); // cada mensagem aceita uma unica vez
    expect(await count('u1', 'c0'), 3);
    expect(await count('u1', 'c1'), 2);
    expect((await messages('u1', 'c0')), hasLength(3));
    expect((await messages('u1', 'c1')), hasLength(2));
    expect(prefs.getString('astrum.chat.migrated.u1'), 'done');
  });

  test('texto > 10000 truncado e mensagens vazias descartadas', () async {
    await prefs.setString(
        'astrum.chat.u1',
        _legacy([
          [
            ('user', 'a' * 12000),
            ('model', ''),
            ('user', '  '),
            ('model', 'ok')
          ],
        ]));
    expect(await migrator().run('u1'), MigrationResult.migrated);
    final m = await messages('u1', 'c0');
    expect(m, hasLength(2));
    expect((m[0]['text'] as String).length, 10000);
    expect(m.map((x) => x['id']), ['m0001', 'm0002']);
    expect(await count('u1', 'c0'), 2);
  });

  test('mais de 50 conversas: todas migram', () async {
    await prefs.setString(
        'astrum.chat.u1',
        _legacy([
          for (var i = 0; i < 60; i++) [('user', 'q$i')]
        ]));
    expect(await migrator().run('u1'), MigrationResult.migrated);
    final all = await db.collection('users/u1/conversations').get();
    expect(all.docs, hasLength(60));
    expect(repo.accepted, 60);
  });

  test('dois uids no aparelho: cada um migra o seu', () async {
    await prefs.setString('astrum.chat.u1', _legacy(two));
    await prefs.setString(
        'astrum.chat.u2',
        _legacy([
          [('user', 'so do u2')],
        ], ids: [
          'x'
        ]));
    expect(await migrator().run('u1'), MigrationResult.migrated);
    expect(prefs.getString('astrum.chat.u2'), isNotNull); // u2 intacto
    expect(prefs.getString('astrum.chat.migrated.u2'), isNull);
    expect(await migrator().run('u2'), MigrationResult.migrated);
    expect(await count('u2', 'x'), 1);
    expect(await count('u1', 'x'), isNull);
    expect(prefs.getString('astrum.chat.u1.bak'), isNotNull);
    expect(prefs.getString('astrum.chat.u2.bak'), isNotNull);
  });

  test('waitForSync que falha: nada apagado; a proxima abertura conclui',
      () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    repo.syncError = StateError('rede');
    expect(await migrator().run('u1'), MigrationResult.incomplete);
    expect(prefs.getString('astrum.chat.u1'), raw);
    expect(prefs.getString('astrum.chat.u1.bak'), isNull);
    expect(prefs.getString('astrum.chat.migrated.u1'), isNull);

    repo.syncError = null;
    final before = repo.accepted;
    expect(await migrator().run('u1'), MigrationResult.migrated);
    expect(repo.accepted, before); // ja estava tudo escrito
  });

  test('waitForSync que nao completa (timeout): nada apagado', () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    repo.syncHangs = true;
    final r =
        await migrator(timeout: const Duration(milliseconds: 50)).run('u1');
    expect(r, MigrationResult.incomplete);
    expect(prefs.getString('astrum.chat.u1'), raw);
    expect(prefs.getString('astrum.chat.u1.bak'), isNull);
  });

  test('offline (commits pendentes): timeout, nada apagado e sem reenvio',
      () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    repo.hang = true;
    final r =
        await migrator(timeout: const Duration(milliseconds: 50)).run('u1');
    expect(r, MigrationResult.incomplete);
    expect(prefs.getString('astrum.chat.u1'), raw);
    expect(prefs.getString('astrum.chat.migrated.u1'), isNull);

    repo.hang = false;
    // c0 ja estava escrita (fila local); so c1 falta.
    expect(await migrator().run('u1'), MigrationResult.migrated);
    expect(repo.accepted, 5); // a contagem local evitou reenviar c0
    expect(await count('u1', 'c0'), 3);
    expect(await count('u1', 'c1'), 2);
  });

  test('.bak so apos conferir messageCount no servidor', () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    repo.serverCountOverride = 1; // servidor ainda nao tem tudo
    expect(await migrator().run('u1'), MigrationResult.incomplete);
    expect(prefs.getString('astrum.chat.u1'), raw);
    expect(prefs.getString('astrum.chat.u1.bak'), isNull);
    expect(prefs.getString('astrum.chat.migrated.u1'), isNull);

    repo.serverCountOverride = null;
    expect(await migrator().run('u1'), MigrationResult.migrated);
    expect(prefs.getString('astrum.chat.u1.bak'), raw);
  });

  test('conversa com mais de 500 mensagens e dividida em partes, sem perda',
      () async {
    await prefs.setString(
        'astrum.chat.u1',
        _legacy([
          [for (var i = 0; i < 1100; i++) ('user', 'm$i')],
        ], ids: [
          'big'
        ]));
    expect(await migrator().run('u1'), MigrationResult.migrated);
    expect(await count('u1', 'big'), 500);
    expect(await count('u1', 'big-p2'), 500);
    expect(await count('u1', 'big-p3'), 100);
    final p2 = await messages('u1', 'big-p2');
    expect(p2.first['text'], 'm500');
    expect(p2.first['id'], 'm0001');
    final c2 = (await db.doc('users/u1/conversations/big-p2').get()).data()!;
    expect(c2['title'], 'Conversa 1 (parte 2)');
    expect(repo.accepted, 1100);
  });

  test('conversa dividida: queda no meio retoma pela contagem de cada parte',
      () async {
    await prefs.setString(
        'astrum.chat.u1',
        _legacy([
          [for (var i = 0; i < 600; i++) ('user', 'm$i')],
        ], ids: [
          'big'
        ]));
    repo.failOnAccepted = 530; // parte 1 completa, parte 2 com 30
    expect(await migrator().run('u1'), MigrationResult.incomplete);
    expect(await count('u1', 'big'), 500);
    expect(await count('u1', 'big-p2'), 30);
    repo.failOnAccepted = null;
    final before = repo.accepted;
    expect(await migrator().run('u1'), MigrationResult.migrated);
    expect(repo.accepted - before, 70);
    expect(await count('u1', 'big-p2'), 100);
    expect((await messages('u1', 'big-p2')).map((m) => m['text']).toList(),
        [for (var i = 500; i < 600; i++) 'm$i']);
  });
}
