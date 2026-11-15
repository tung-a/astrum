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
  bool denyAll = false; // nega tudo (permission-denied)
  int newCalls = 0; // tentativas com isNew
  bool hang = false; // grava, mas o Future nunca completa (offline)
  int? serverCountOverride; // resposta de fromServer
  Object? syncError;
  bool syncHangs = false;
  Future<void> Function()? onSync; // gancho (ex.: o legado muda no meio)

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
    if (isNew) newCalls++;
    _tail = _tail.then((_) async {
      try {
        final conv = await db.doc('users/$uid/conversations/$convId').get();
        final msg = await db
            .doc('users/$uid/conversations/$convId/messages/${message.id}')
            .get();
        if (failOnAccepted != null && accepted >= failOnAccepted!) {
          throw _err('unavailable');
        }
        if (denyAll) throw _err('permission-denied');
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
    await onSync?.call();
    if (syncError != null) throw syncError!;
    if (syncHangs) return Completer<void>().future;
  }
}

/// Store cujo shared_preferences "nao confirma" a escrita do .bak.
class _NoBackupStore extends LegacyChatStore {
  _NoBackupStore(super.prefs);
  @override
  Future<bool> backup(String uid, String raw) async => false;
}

/// Store cuja marca de migracao falha (setString devolve false).
class _NoBaseStore extends LegacyChatStore {
  _NoBaseStore(super.prefs);
  @override
  Future<bool> setMigrationBase(String uid, int millis) async => false;
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
    String? Function()? uid,
  }) =>
      LegacyChatMigrator(
          legacy: s ?? store,
          repository: r ?? repo,
          now: () => now,
          currentUid: uid,
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

  test('estrutura irrecuperavel (raiz nao-mapa, conversations nao-lista)',
      () async {
    const bad1 = '[1,2,3]';
    await prefs.setString('astrum.chat.u1', bad1);
    expect(await migrator().run('u1'), MigrationResult.corrupt);
    const bad2 = '{"conversations":"texto"}';
    await prefs.setString('astrum.chat.u2', bad2);
    expect(await migrator().run('u2'), MigrationResult.corrupt);
    expect(prefs.getString('astrum.chat.u2'), bad2);
    expect(prefs.getString('astrum.chat.u2.bak'), bad2);
  });

  test('parse tolerante: role/text atipicos e itens estranhos nao corrompem',
      () async {
    await prefs.setString(
        'astrum.chat.u1',
        jsonEncode({
          'conversations': [
            {
              'id': 'ok',
              'title': 5,
              'messages': [
                {'role': 7, 'text': 'tipo errado de role'},
                {'role': 'model', 'text': 99},
                42,
                {'role': 'model', 'text': 'resposta'},
              ],
            },
            {'id': null, 'messages': 'nao-lista'},
            {
              'id': 'a/b',
              'messages': [
                {'text': 'id invalido vira legacy-<hash>'}
              ]
            },
            'lixo',
          ],
        }));
    expect(await migrator().run('u1'), MigrationResult.migrated);
    final m = await messages('u1', 'ok');
    expect(m.map((x) => x['text']), ['tipo errado de role', 'resposta']);
    expect(m.map((x) => x['role']), ['user', 'model']);
    final c = (await db.doc('users/u1/conversations/ok').get()).data()!;
    expect(c['title'], 'Conversa');
    expect(
        await count(
            'u1',
            LegacyChatMigrator.fallbackId(
                'Conversa', 'id invalido vira legacy-<hash>')),
        1);
    expect(await count('u1', LegacyChatMigrator.fallbackId('Conversa', '')),
        isNull); // sem mensagens
    expect(prefs.getString('astrum.chat.migrated.u1'), 'done');
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
    expect((c0['updatedAt'] as Timestamp).toDate().isAtSameMomentAs(now),
        isTrue);
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

  test('execucoes concorrentes do mesmo uid compartilham uma so execucao',
      () async {
    await prefs.setString('astrum.chat.u1', _legacy(two));
    final results =
        await Future.wait([migrator().run('u1'), migrator().run('u1')]);
    expect(results, [MigrationResult.migrated, MigrationResult.migrated]);
    expect(repo.accepted, 5);
    expect(await count('u1', 'c0'), 3);
    expect(prefs.getString('astrum.chat.migrated.u1'), 'done');
    // terminada a execucao, uma nova chamada volta a rodar normalmente
    expect(await migrator().run('u1'), MigrationResult.alreadyDone);
  });

  test('lacuna permanente: lista ids do servidor e envia so os que faltam',
      () async {
    await prefs.setString('astrum.chat.u1', _legacy(two));
    // Outro aparelho deixou m0001 e m0003 (contador 2): enviar m0003 sempre
    // falha (existe), o contador nunca avanca pela contagem.
    final ts = Timestamp.fromDate(now);
    await db.doc('users/u1/conversations/c0').set({
      'title': 'Conversa 1',
      'createdAt': ts,
      'updatedAt': ts,
      'messageCount': 2,
      'schemaVersion': 1,
    });
    for (final id in ['m0001', 'm0003']) {
      await db
          .doc('users/u1/conversations/c0/messages/$id')
          .set({'role': 'user', 'text': 'x', 'createdAt': ts});
    }
    expect(await migrator().run('u1'), MigrationResult.migrated);
    expect((await messages('u1', 'c0')).map((m) => m['id']).toSet(),
        {'m0001', 'm0002', 'm0003'});
    expect(await count('u1', 'c0'), 3);
    expect(repo.accepted, 3); // so m0002 de c0 + 2 de c1
  });

  test('legado muda durante a migracao: nada apagado, sem .bak', () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    repo.onSync = () async {
      await prefs.setString(
          'astrum.chat.u1',
          _legacy([
            [('user', 'nova mensagem local')]
          ]));
    };
    expect(await migrator().run('u1'), MigrationResult.incomplete);
    expect(prefs.getString('astrum.chat.u1'), isNot(raw));
    expect(prefs.getString('astrum.chat.u1.bak'), isNull);
    expect(prefs.getString('astrum.chat.migrated.u1'), isNull);
  });

  test('.bak nao confirmado: original nunca e removido (migracao e corrupto)',
      () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    final s = _NoBackupStore(prefs);
    expect(await migrator(s: s).run('u1'), MigrationResult.incomplete);
    expect(prefs.getString('astrum.chat.u1'), raw);
    expect(prefs.getString('astrum.chat.migrated.u1'), isNull);

    await prefs.setString('astrum.chat.u2', '{"conversations": 5}');
    expect(await migrator(s: s).run('u2'), MigrationResult.incomplete);
    expect(prefs.getString('astrum.chat.u2'), isNotNull);
    expect(prefs.getString('astrum.chat.migrated.u2'), isNull);
  });

  test('base de datas nao gravada: aborta sem enviar', () async {
    await prefs.setString('astrum.chat.u1', _legacy(two));
    expect(await migrator(s: _NoBaseStore(prefs)).run('u1'),
        MigrationResult.incomplete);
    expect(repo.accepted, 0);
  });

  test('datas sinteticas: base gravada na 1a tentativa e reutilizada',
      () async {
    await prefs.setString('astrum.chat.u1', _legacy(two));
    repo.failOnAccepted = 1; // 1a tentativa falha no meio
    expect(await migrator().run('u1'), MigrationResult.incomplete);
    expect(prefs.getInt('astrum.chat.migbase.u1'), now.millisecondsSinceEpoch);

    repo.failOnAccepted = null;
    final later = LegacyChatMigrator(
        legacy: store,
        repository: repo,
        now: () => now.add(const Duration(days: 3)), // relogio avancou
        syncTimeout: const Duration(milliseconds: 200));
    expect(await later.run('u1'), MigrationResult.migrated);
    final c1 = (await db.doc('users/u1/conversations/c1').get()).data()!;
    expect(
        (c1['updatedAt'] as Timestamp)
            .toDate()
            .isAtSameMomentAs(now.add(const Duration(seconds: 1))),
        isTrue);
    final m0 = await messages('u1', 'c0');
    final ts = [for (final m in m0) (m['createdAt'] as Timestamp).toDate()];
    for (var i = 1; i < ts.length; i++) {
      expect(ts[i].isAfter(ts[i - 1]), isTrue);
    }
    expect(ts.every((t) => !t.isBefore(now)), isTrue); // ancorado no inicio
    expect(prefs.getInt('astrum.chat.migbase.u1'), isNull); // limpo ao fim
  });

  test('legado cresce entre tentativas: datas e ordem estaveis, sem duplicar',
      () async {
    await prefs.setString('astrum.chat.u1', _legacy(two));
    repo.failOnAccepted = 4; // c0 completa (3); c1 so com m0001
    expect(await migrator().run('u1'), MigrationResult.incomplete);
    final c0Before = await messages('u1', 'c0');
    final c1Before = await messages('u1', 'c1');
    final convBefore = [
      for (final id in ['c0', 'c1'])
        (await db.doc('users/u1/conversations/$id').get()).data()!
    ];

    // O legado cresce ao fim: mais uma mensagem em c1 e uma conversa nova.
    await prefs.setString(
        'astrum.chat.u1',
        _legacy([
          two[0],
          [...two[1], ('user', 'terceira')],
          [('user', 'nova conversa')],
        ]));
    repo.failOnAccepted = null;
    final before = repo.accepted;
    final later = LegacyChatMigrator(
        legacy: store,
        repository: repo,
        now: () => now.add(const Duration(days: 1)),
        syncTimeout: const Duration(milliseconds: 200));
    expect(await later.run('u1'), MigrationResult.migrated);
    expect(repo.accepted - before, 3); // m0002, m0003 de c1 + c2

    expect(await messages('u1', 'c0'), c0Before);
    final c1After = await messages('u1', 'c1');
    expect(c1After.map((m) => m['id']), ['m0001', 'm0002', 'm0003']);
    expect(c1After.first, c1Before.first);
    for (var i = 0; i < 2; i++) {
      final d = (await db.doc('users/u1/conversations/c$i').get()).data()!;
      expect(d['createdAt'], convBefore[i]['createdAt']);
      expect(d['updatedAt'], convBefore[i]['updatedAt']);
    }
    final u = [
      for (var i = 0; i < 3; i++)
        ((await db.doc('users/u1/conversations/c$i').get()).data()!['updatedAt']
                as Timestamp)
            .toDate()
    ];
    expect(u[0].isBefore(u[1]) && u[1].isBefore(u[2]), isTrue);
    expect(await count('u1', 'c0'), 3);
    expect(await count('u1', 'c1'), 3);
    expect(await count('u1', 'c2'), 1);
  });

  test('id de fallback derivado do conteudo, nao da posicao na lista',
      () async {
    String raw(List<(String, String)> items) => jsonEncode({
          'conversations': [
            for (final (title, text) in items)
              {
                'title': title,
                'messages': [
                  {'role': 'user', 'text': text}
                ],
              },
          ],
        });
    await prefs.setString('astrum.chat.u1', raw([('A', 'um'), ('B', 'dois')]));
    repo.failOnAccepted = 1; // so a 1a conversa chega a nascer
    expect(await migrator().run('u1'), MigrationResult.incomplete);
    final idA = LegacyChatMigrator.fallbackId('A', 'um');
    final idB = LegacyChatMigrator.fallbackId('B', 'dois');
    expect(idA, isNot(idB));
    expect(await count('u1', idA), 1);
    // ordem do legado mudou entre tentativas: A continua sendo A.
    await prefs.setString('astrum.chat.u1', raw([('B', 'dois'), ('A', 'um')]));
    repo.failOnAccepted = null;
    final before = repo.accepted;
    expect(await migrator().run('u1'), MigrationResult.migrated);
    expect(repo.accepted - before, 1); // so B; A nao foi reenviada
    expect(await count('u1', idB), 1);
  });

  test('uid deixa de ser o usuario atual: aborta sem insistir', () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    expect(await migrator(uid: () => 'outro').run('u1'),
        MigrationResult.incomplete);
    expect(repo.accepted, 0);
    expect(prefs.getString('astrum.chat.u1'), raw);
    expect(prefs.getString('astrum.chat.migrated.u1'), isNull);
    expect(await migrator(uid: () => null).run('u1'),
        MigrationResult.incomplete); // deslogado
    // uid correto: segue normalmente
    expect(await migrator(uid: () => 'u1').run('u1'), MigrationResult.migrated);
  });

  test('conversa existente com contador inflado e sem mensagens: incomplete',
      () async {
    final raw = _legacy(two);
    await prefs.setString('astrum.chat.u1', raw);
    final ts = Timestamp.fromDate(now);
    await db.doc('users/u1/conversations/c0').set({
      'title': 'Conversa 1',
      'createdAt': ts,
      'updatedAt': ts,
      'messageCount': 1, // inflado: nenhuma mensagem existe
      'schemaVersion': 1,
    });
    repo.denyAll = true; // o servidor nega tudo
    expect(await migrator().run('u1'), MigrationResult.incomplete);
    expect(repo.newCalls, 0); // nao tentou recriar a conversa (set negado)
    expect(prefs.getString('astrum.chat.u1'), raw);
    expect(prefs.getString('astrum.chat.migrated.u1'), isNull);
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
