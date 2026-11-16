import 'package:astrum/features/social/data/social_repository.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Injeta falha na proxima escrita (fake_cloud_firestore nao avalia regras).
class _Repo extends SocialRepository {
  _Repo(super.db);
  final errors = <String>[]; // codigos a lancar, um por chamada

  @override
  Future<T> runGuarded<T>(Future<T> Function() op) async {
    if (errors.isNotEmpty) {
      throw FirebaseException(
          plugin: 'cloud_firestore', code: errors.removeAt(0));
    }
    return op();
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late _Repo repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = _Repo(db);
  });

  Future<Map<String, dynamic>?> read(String a, String b) async {
    final d = await db.doc('friendships/${pairIdOf(a, b)}').get();
    return d.data();
  }

  Future<void> seed(String a, String b, Map<String, dynamic> over) =>
      db.doc('friendships/${pairIdOf(a, b)}').set({
        'uids': [a, b]..sort(),
        'requesterUid': a,
        'requesterName': 'Req',
        'status': 'pending',
        ...over,
      });

  group('requestFriendship', () {
    test('cria o pedido pendente com uids ordenados', () async {
      final r =
          await repo.requestFriendship(me: 'zed', myName: 'Zed', other: 'ana');
      expect(r, RequestOutcome.sent);
      final d = (await read('zed', 'ana'))!;
      expect(d['uids'], ['ana', 'zed']);
      expect(d['requesterUid'], 'zed');
      expect(d['requesterName'], 'Zed');
      expect(d['status'], 'pending');
      expect(d.containsKey('createdAt'), isTrue);
      expect(d.keys.toSet(),
          {'uids', 'requesterUid', 'requesterName', 'status', 'createdAt'});
    });

    test('segundo pedido do mesmo remetente: alreadySent e nada muda',
        () async {
      await repo.requestFriendship(me: 'a', myName: 'A', other: 'b');
      final r = await repo.requestFriendship(me: 'a', myName: 'A2', other: 'b');
      expect(r, RequestOutcome.alreadySent);
      expect((await read('a', 'b'))!['requesterName'], 'A');
    });

    test('pedido cruzado (sequencial): o segundo vira amizade, um documento',
        () async {
      await repo.requestFriendship(me: 'a', myName: 'A', other: 'b');
      final r = await repo.requestFriendship(me: 'b', myName: 'B', other: 'a');
      expect(r, RequestOutcome.crossAccepted);
      final d = (await read('a', 'b'))!;
      expect(d['status'], 'accepted');
      expect(d['requesterUid'], 'a');
      expect(d['responderName'], 'B');
      expect((await db.collection('friendships').get()).docs, hasLength(1));
    });

    test('ja amigos: alreadyFriends', () async {
      await seed('a', 'b', {'status': 'accepted', 'responderName': 'B'});
      expect(await repo.requestFriendship(me: 'b', myName: 'B', other: 'a'),
          RequestOutcome.alreadyFriends);
    });

    test('meu pedido recusado pelo outro: alreadySent (recusa silenciosa)',
        () async {
      await seed('a', 'b', {'status': 'declined', 'declinedBy': 'b'});
      expect(await repo.requestFriendship(me: 'a', myName: 'A', other: 'b'),
          RequestOutcome.alreadySent);
    });

    test('lapide minha ou de amizade removida: unavailable (generico)',
        () async {
      // eu recusei o pedido dele e ele tenta de novo
      await seed('a', 'b', {'status': 'declined', 'declinedBy': 'b'});
      expect(await repo.requestFriendship(me: 'b', myName: 'B', other: 'a'),
          RequestOutcome.unavailable);
      // amizade removida pelo outro: nao e "pedido enviado"
      await seed('c', 'd', {
        'status': 'declined',
        'declinedBy': 'd',
        'responderName': 'D',
      });
      expect(await repo.requestFriendship(me: 'c', myName: 'C', other: 'd'),
          RequestOutcome.unavailable);
    });

    test('permission-denied das regras: unavailable; unavailable de rede sobe',
        () async {
      repo.errors.add('permission-denied');
      expect(await repo.requestFriendship(me: 'a', myName: 'A', other: 'b'),
          RequestOutcome.unavailable);
      repo.errors.add('unavailable');
      await expectLater(
          repo.requestFriendship(me: 'a', myName: 'A', other: 'b'),
          throwsA(isA<FirebaseException>()
              .having((e) => e.code, 'code', 'unavailable')));
    });
  });

  group('aceitar, recusar, remover, cancelar, desbloquear', () {
    test('aceitar grava status e nome; aceite duplo e idempotente', () async {
      await seed('a', 'b', {});
      expect(await repo.acceptFriendship(me: 'b', myName: 'B', other: 'a'),
          ActionOutcome.done);
      final d = (await read('a', 'b'))!;
      expect(d['status'], 'accepted');
      expect(d['responderName'], 'B');
      // segundo aparelho: as regras negam; a releitura acha 'accepted'
      repo.errors.add('permission-denied');
      expect(await repo.acceptFriendship(me: 'b', myName: 'B', other: 'a'),
          ActionOutcome.done);
    });

    test('aceitar quando o pedido sumiu (cancelado): gone', () async {
      repo.errors.add('permission-denied');
      expect(await repo.acceptFriendship(me: 'b', myName: 'B', other: 'a'),
          ActionOutcome.gone);
      // documento inexistente de verdade (not-found do servidor)
      expect(await repo.acceptFriendship(me: 'b', myName: 'B', other: 'a'),
          ActionOutcome.gone);
    });

    test('recusar vira lapide com declinedBy', () async {
      await seed('a', 'b', {});
      expect(await repo.declineFriendship(me: 'b', other: 'a'),
          ActionOutcome.done);
      final d = (await read('a', 'b'))!;
      expect(d['status'], 'declined');
      expect(d['declinedBy'], 'b');
      expect(d.containsKey('responderName'), isFalse);
    });

    test('remover amizade vira lapide de quem removeu; mantem responderName',
        () async {
      await seed('a', 'b', {'status': 'accepted', 'responderName': 'B'});
      expect(
          await repo.removeFriendship(me: 'a', other: 'b'), ActionOutcome.done);
      final d = (await read('a', 'b'))!;
      expect(d['status'], 'declined');
      expect(d['declinedBy'], 'a');
      expect(d['responderName'], 'B');
    });

    test(
        'remover/recusar de novo apos o outro lado agir: done se fui eu, gone '
        'se foi outra pessoa', () async {
      await seed('a', 'b', {
        'status': 'declined',
        'declinedBy': 'a',
      });
      repo.errors.add('permission-denied');
      expect(
          await repo.removeFriendship(me: 'a', other: 'b'), ActionOutcome.done);
      repo.errors.add('permission-denied');
      expect(
          await repo.removeFriendship(me: 'b', other: 'a'), ActionOutcome.gone);
    });

    test('cancelar apaga o pedido; cancelar o que ja sumiu e done', () async {
      await seed('a', 'b', {});
      expect(await repo.cancelRequest(me: 'a', other: 'b'), ActionOutcome.done);
      expect(await read('a', 'b'), isNull);
      repo.errors.add('permission-denied');
      expect(await repo.cancelRequest(me: 'a', other: 'b'), ActionOutcome.done);
    });

    test('cancelar um pedido ja aceito: gone', () async {
      await seed('a', 'b', {'status': 'accepted', 'responderName': 'B'});
      repo.errors.add('permission-denied');
      expect(await repo.cancelRequest(me: 'a', other: 'b'), ActionOutcome.gone);
    });

    test('desbloquear apaga a lapide', () async {
      await seed('a', 'b', {'status': 'declined', 'declinedBy': 'b'});
      expect(await repo.unblock(me: 'b', other: 'a'), ActionOutcome.done);
      expect(await read('a', 'b'), isNull);
      // e o par pode pedir de novo
      expect(await repo.requestFriendship(me: 'a', myName: 'A', other: 'b'),
          RequestOutcome.sent);
    });

    test('erro de rede sobe (nao vira gone)', () async {
      repo.errors.add('unavailable');
      await expectLater(
          repo.declineFriendship(me: 'b', other: 'a'),
          throwsA(isA<FirebaseException>()
              .having((e) => e.code, 'code', 'unavailable')));
    });
  });

  group('watchFriendships e exclusao', () {
    test('consulta so as relacoes do uid e ignora documento malformado',
        () async {
      await seed('a', 'b', {});
      await seed('a', 'c', {'status': 'accepted', 'responderName': 'C'});
      await seed('x', 'y', {});
      await db.doc('friendships/a_z').set({'uids': 'lixo'});
      final list = await repo.watchFriendships('a').first;
      expect(list.map((f) => f.id).toSet(), {'a_b', 'a_c'});
      final other = await repo.watchFriendships('x').first;
      expect(other.map((f) => f.id), ['x_y']);
    });

    test('publicNameOf devolve o nome publico ou null', () async {
      await db.doc('publicProfiles/b').set({'name': 'Bia'});
      expect(await repo.publicNameOf('b'), 'Bia');
      expect(await repo.publicNameOf('z'), isNull);
    });

    test('deleteAllFriendships: mais de 400, so as do uid, idempotente',
        () async {
      for (var i = 0; i < 450; i++) {
        await db.doc('friendships/a_u${i.toString().padLeft(4, '0')}').set({
          'uids': ['a', 'u${i.toString().padLeft(4, '0')}'],
          'requesterUid': 'a',
          'status': 'pending',
        });
      }
      await seed('x', 'y', {});
      await repo.deleteAllFriendships('a');
      await repo.deleteAllFriendships('a');
      final left = await db.collection('friendships').get();
      expect(left.docs.map((d) => d.id), ['x_y']);
    });
  });
}
