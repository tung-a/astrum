// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:astrum/core/firebase/paged_delete.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  Future<void> seed(int n, {String owner = 'u1'}) async {
    for (var i = 0; i < n; i += 400) {
      final b = db.batch();
      for (var j = i; j < i + 400 && j < n; j++) {
        b.set(db.doc('items/$owner-$j'), {'userId': owner});
      }
      await b.commit();
    }
  }

  Query<Map<String, dynamic>> mine() =>
      db.collection('items').where('userId', isEqualTo: 'u1');

  test('apaga mais de uma pagina (950 > 2x400) e preserva o de outro uid',
      () async {
    await seed(950);
    await seed(3, owner: 'u2');
    final ids = await deleteQueryPaged(mine());
    expect(ids, hasLength(950));
    expect((await mine().get()).docs, isEmpty);
    expect((await db.collection('items').get()).docs, hasLength(3));
  });

  test('colecao vazia: nada a apagar, 1 leitura', () async {
    var reads = 0;
    final ids = await deleteQueryPaged(mine(), readPage: (q) {
      reads++;
      return readServerPage(q);
    });
    expect(ids, isEmpty);
    expect(reads, 1);
  });

  test('retomada: segunda execucao depois de falha termina o trabalho',
      () async {
    await seed(900);
    var commits = 0;
    await expectLater(
      deleteQueryPaged(mine(), commit: (b) {
        commits++;
        if (commits == 2) return Future.error(const ServerOfflineException());
        return b.commit();
      }),
      throwsA(isA<ServerOfflineException>()),
    );
    expect((await mine().get()).docs, hasLength(500)); // 1a pagina de 400 foi
    final ids = await deleteQueryPaged(mine());
    expect(ids, hasLength(500));
    expect((await mine().get()).docs, isEmpty);
  });

  test('offline na leitura: ServerOfflineException e nada apagado', () async {
    await seed(5);
    await expectLater(
      deleteQueryPaged(mine(),
          readPage: (_) => Future.error(const ServerOfflineException())),
      throwsA(isA<ServerOfflineException>()),
    );
    expect((await mine().get()).docs, hasLength(5));
  });

  test('FirebaseException unavailable na leitura vira ServerOfflineException',
      () async {
    await seed(1);
    expect(
      () => readServerPage(_ThrowingQuery(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'))),
      throwsA(isA<ServerOfflineException>()),
    );
  });

  test('commit que nao completa no prazo vira ServerOfflineException',
      () async {
    await seed(5);
    await expectLater(
      deleteQueryPaged(mine(),
          commitTimeout: const Duration(milliseconds: 20),
          commit: (_) => Completer<void>().future),
      throwsA(isA<ServerOfflineException>()),
    );
    expect((await mine().get()).docs, hasLength(5));
  });

  test('commit com unavailable vira offline; resource-exhausted sobe como esta',
      () async {
    await seed(5);
    await expectLater(
      deleteQueryPaged(mine(),
          commit: (_) => Future.error(FirebaseException(
              plugin: 'cloud_firestore', code: 'unavailable'))),
      throwsA(isA<ServerOfflineException>()),
    );
    await expectLater(
      deleteQueryPaged(mine(),
          commit: (_) => Future.error(FirebaseException(
              plugin: 'cloud_firestore', code: 'resource-exhausted'))),
      throwsA(isA<FirebaseException>()
          .having((e) => e.code, 'code', 'resource-exhausted')),
    );
  });

  test('maxIds limita so a lista devolvida, nao o apagamento', () async {
    await seed(30);
    final ids = await deleteQueryPaged(mine(), page: 10, maxIds: 12);
    expect(ids, hasLength(12));
    expect((await mine().get()).docs, isEmpty);
  });
}

class _ThrowingQuery implements Query<Map<String, dynamic>> {
  _ThrowingQuery(this.error);
  final Object error;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      Future.error(error);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
