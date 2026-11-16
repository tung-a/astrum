import 'package:astrum/features/social/domain/friendship.dart';
import 'package:flutter_test/flutter_test.dart';

Friendship _f(
  String a,
  String b, {
  String requester = '',
  FriendshipStatus status = FriendshipStatus.pending,
  String? responderName,
  String? declinedBy,
  String requesterName = 'Req',
}) =>
    Friendship(
      id: pairIdOf(a, b),
      uids: [a, b]..sort(),
      requesterUid: requester.isEmpty ? a : requester,
      requesterName: requesterName,
      status: status,
      responderName: responderName,
      declinedBy: declinedBy,
    );

void main() {
  group('pairIdOf (equivalente a pairId de firestore.rules)', () {
    const cases = <(String, String, String)>[
      ('alice', 'bob', 'alice_bob'),
      ('bob', 'alice', 'alice_bob'),
      ('a', 'b', 'a_b'),
      ('Z', 'a', 'Z_a'), // maiuscula antes de minuscula (ordem de codepoint)
      ('abc1', 'abc10', 'abc1_abc10'),
      (
        'aB3dE5gH7jK9mN1pQ3sT5vW7yZ01',
        'zY9xW7vU5tS3rQ1pO9nM7lK5jI3h',
        'aB3dE5gH7jK9mN1pQ3sT5vW7yZ01_zY9xW7vU5tS3rQ1pO9nM7lK5jI3h'
      ),
    ];
    for (final (a, b, want) in cases) {
      test('$a / $b', () {
        expect(pairIdOf(a, b), want);
        expect(pairIdOf(b, a), want);
      });
    }

    test('o primeiro uid do id e sempre o menor', () {
      final id = pairIdOf('u9', 'u10');
      final parts = id.split('_');
      expect(parts[0].compareTo(parts[1]) < 0, isTrue);
    });
  });

  group('Friendship.fromData', () {
    Map<String, dynamic> base() => {
          'uids': ['a', 'b'],
          'requesterUid': 'a',
          'requesterName': 'Ana',
          'status': 'pending',
        };

    test('documento valido', () {
      final f = Friendship.fromData('a_b', base())!;
      expect(f.status, FriendshipStatus.pending);
      expect(f.otherUid('a'), 'b');
      expect(f.otherUid('b'), 'a');
      expect(f.otherName('b'), 'Ana');
      expect(f.otherName('a'), isNull); // remetente ainda nao sabe o nome
    });

    test('formato invalido vira null (nunca quebra)', () {
      expect(Friendship.fromData('x', {...base(), 'status': 'x'}), isNull);
      expect(
          Friendship.fromData('x', {
            ...base(),
            'uids': ['a']
          }),
          isNull);
      expect(
          Friendship.fromData('x', {
            ...base(),
            'uids': ['a', 1]
          }),
          isNull);
      expect(
          Friendship.fromData('x', {...base(), 'requesterUid': 'c'}), isNull);
      expect(Friendship.fromData('x', {}), isNull);
    });

    test('nome ausente cai em Viajante', () {
      final f = Friendship.fromData('a_b', {...base(), 'requesterName': ''})!;
      expect(f.requesterName, 'Viajante');
    });
  });

  group('viewFor', () {
    test('lista vazia', () {
      final v = viewFor('me', const []);
      expect(v.friends, isEmpty);
      expect(v.incoming, isEmpty);
      expect(v.outgoing, isEmpty);
      expect(v.blockedByMe, isEmpty);
    });

    test('separa amigos, recebidos, enviados e bloqueados por mim', () {
      final v = viewFor('me', [
        // amigo: eu pedi, ele aceitou
        _f('me', 'zed',
            requester: 'me',
            status: FriendshipStatus.accepted,
            responderName: 'Zed'),
        // amigo: ele pediu, eu aceitei
        _f('me', 'ana',
            requester: 'ana',
            status: FriendshipStatus.accepted,
            requesterName: 'Ana',
            responderName: 'Eu'),
        // recebido pendente
        _f('me', 'bia', requester: 'bia', requesterName: 'Bia'),
        // enviado pendente
        _f('me', 'cris', requester: 'me', requesterName: 'Eu'),
        // eu recusei o pedido dele
        _f('me', 'dani',
            requester: 'dani',
            status: FriendshipStatus.declined,
            declinedBy: 'me',
            requesterName: 'Dani'),
        // alheia (nao deveria vir, mas e ignorada)
        _f('x', 'y'),
      ]);
      expect(v.friends.map((f) => f.name), ['Ana', 'Zed']);
      expect(v.friends.map((f) => f.id), ['ana', 'zed']);
      expect(v.incoming.map((f) => f.requesterName), ['Bia']);
      expect(v.outgoing.map((f) => f.otherUid('me')), ['cris']);
      expect(v.blockedByMe.map((f) => f.otherName('me')), ['Dani']);
      expect(v.pendingOutgoingCount, 1);
    });

    test(
        'pedido recusado pelo outro segue em enviados (silencio) mas nao '
        'conta na cota', () {
      final v = viewFor('me', [
        _f('me', 'eva',
            requester: 'me',
            status: FriendshipStatus.declined,
            declinedBy: 'eva',
            requesterName: 'Eu'),
        _f('me', 'ivo', requester: 'me', requesterName: 'Eu'),
      ]);
      expect(v.outgoing, hasLength(2));
      expect(v.pendingOutgoingCount, 1);
      expect(v.blockedByMe, isEmpty);
    });

    test('amizade removida pelo outro some para quem foi removido', () {
      final v = viewFor('me', [
        _f('me', 'eva',
            requester: 'me',
            status: FriendshipStatus.declined,
            declinedBy: 'eva',
            responderName: 'Eva'),
        _f('me', 'ivo',
            requester: 'ivo',
            status: FriendshipStatus.declined,
            declinedBy: 'ivo',
            responderName: 'Eu'),
      ]);
      expect(v.friends, isEmpty);
      expect(v.outgoing, isEmpty);
      expect(v.incoming, isEmpty);
      expect(v.blockedByMe, isEmpty);
    });

    test('amizade que eu removi aparece em bloqueados com o nome do outro', () {
      final v = viewFor('me', [
        _f('me', 'eva',
            requester: 'me',
            status: FriendshipStatus.declined,
            declinedBy: 'me',
            responderName: 'Eva'),
      ]);
      expect(v.blockedByMe.single.otherName('me'), 'Eva');
    });

    test('amigo sem nome conhecido cai em Viajante', () {
      final v = viewFor('me', [
        _f('me', 'eva', requester: 'me', status: FriendshipStatus.accepted),
      ]);
      expect(v.friends.single.name, 'Viajante');
    });
  });
}
