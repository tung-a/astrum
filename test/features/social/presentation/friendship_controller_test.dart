import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/presentation/friendship_controller.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/make_container.dart';

Friendship _f(String other,
        {String requester = '',
        FriendshipStatus status = FriendshipStatus.pending,
        String? responderName,
        String? declinedBy}) =>
    Friendship(
      id: pairIdOf('u1', other),
      uids: ['u1', other]..sort(),
      requesterUid: requester.isEmpty ? 'u1' : requester,
      requesterName: 'Nome $other',
      status: status,
      responderName: responderName,
      declinedBy: declinedBy,
    );

void main() {
  late FakeSocialRepository social;
  late ProviderContainer c;

  setUp(() => social = FakeSocialRepository());

  Future<FriendshipController> setup({
    bool loggedIn = true,
    List<Friendship> relations = const [],
  }) async {
    c = await makeContainer(
      user: loggedIn ? testUser() : null,
      overrides: [socialRepositoryProvider.overrideWithValue(social)],
    );
    addTearDown(c.dispose);
    c.listen(friendshipsViewProvider, (_, __) {});
    social.friendshipsCtl.add(relations);
    await Future<void>.delayed(Duration.zero);
    return c.read(friendshipControllerProvider.notifier);
  }

  group('lookup', () {
    test('e-mail inexistente, o proprio e vazio: mensagens', () async {
      final ctl = await setup();
      var r = await ctl.lookup('nao@existe.com');
      expect(r.friend, isNull);
      expect(r.message, friendRequestGeneric);
      social.usersByEmail['u1@example.com'] =
          const Friend(id: 'u1', name: 'Eu');
      r = await ctl.lookup('u1@example.com');
      expect(r.message, friendRequestGeneric);
      r = await ctl.lookup('   ');
      expect(r.message, 'Digite o e-mail de um viajante.');
      expect(social.searchedEmails, ['nao@existe.com', 'u1@example.com']);
    });

    test('achado: devolve o viajante para confirmar (nada gravado)', () async {
      social.usersByEmail['l@x.com'] = const Friend(id: 'u2', name: 'Luna');
      final ctl = await setup();
      final r = await ctl.lookup('l@x.com');
      expect(r.friend?.id, 'u2');
      expect(r.message, isNull);
      expect(social.requests, isEmpty);
    });

    test('ja amigos e pedido ja enviado tem mensagens proprias', () async {
      social.usersByEmail['f@x.com'] = const Friend(id: 'f', name: 'Fê');
      social.usersByEmail['p@x.com'] = const Friend(id: 'p', name: 'Pê');
      final ctl = await setup(relations: [
        _f('f', status: FriendshipStatus.accepted, responderName: 'Fê'),
        _f('p'),
      ]);
      expect((await ctl.lookup('f@x.com')).message, friendAlreadyFriends);
      expect((await ctl.lookup('p@x.com')).message, friendAlreadySent);
    });

    test('cota de 20 pedidos pendentes (so no cliente); recusados nao contam',
        () async {
      social.usersByEmail['n@x.com'] = const Friend(id: 'n', name: 'Nova');
      final ctl = await setup(relations: [
        for (var i = 0; i < maxPendingOutgoingClient - 1; i++)
          _f('x${i.toString().padLeft(2, '0')}'),
        _f('recusado',
            status: FriendshipStatus.declined, declinedBy: 'recusado'),
      ]);
      expect((await ctl.lookup('n@x.com')).friend?.id, 'n'); // 19 pendentes
      final ctl2 = await setup(relations: [
        for (var i = 0; i < maxPendingOutgoingClient; i++)
          _f('x${i.toString().padLeft(2, '0')}'),
      ]);
      final r = await ctl2.lookup('n@x.com');
      expect(r.message, friendRequestTooMany);
      expect(social.searchedEmails, ['n@x.com']); // nem busca na cota cheia
    });

    test('sem perfil nao busca', () async {
      final off = await setup(loggedIn: false);
      expect((await off.lookup('a@x.com')).message, friendFailed);
      expect(social.searchedEmails, isEmpty);
    });
  });

  group('sendRequest: textos por resultado', () {
    const luna = Friend(id: 'u2', name: 'Luna');

    test('um texto por resultado e a mesma frase generica para a recusa',
        () async {
      final ctl = await setup();
      final expected = {
        RequestOutcome.sent: 'Pedido enviado a Luna.',
        RequestOutcome.crossAccepted: friendCrossAccepted,
        RequestOutcome.alreadySent: friendAlreadySent,
        RequestOutcome.alreadyFriends: friendAlreadyFriends,
        RequestOutcome.unavailable: friendRequestGeneric,
      };
      for (final e in expected.entries) {
        social.requestOutcome = e.key;
        expect(await ctl.sendRequest(luna), e.value, reason: '${e.key}');
      }
      expect(social.requests.first, (me: 'u1', myName: 'Teste', other: 'u2'));
    });

    test('mensagens genericas identicas: busca vazia, lapide e conta excluida',
        () async {
      final ctl = await setup();
      social.requestOutcome = RequestOutcome.unavailable; // lapide/busca off
      final a = await ctl.sendRequest(luna);
      final b = (await ctl.lookup('nao@existe.com')).message;
      expect(a, b);
      expect(a, 'Não foi possível enviar o pedido a esse e-mail.');
    });

    test('offline e erro desconhecido: textos neutros, sem detalhe', () async {
      final ctl = await setup();
      social.friendshipError =
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      expect(await ctl.sendRequest(luna), friendOffline);
      social.friendshipError = StateError('segredo@x.com');
      final t = await ctl.sendRequest(luna);
      expect(t, friendFailed);
      expect(t.contains('segredo'), isFalse);
    });

    test('sem perfil nao envia', () async {
      final ctl = await setup(loggedIn: false);
      expect(await ctl.sendRequest(luna), friendFailed);
      expect(social.requests, isEmpty);
    });
  });

  group('acoes', () {
    test('aceitar, recusar, cancelar, desbloquear e remover: texto e chamada',
        () async {
      final ctl = await setup();
      final incoming = _f('u2', requester: 'u2');
      expect(await ctl.accept(incoming), 'Nome u2 entrou na sua constelação.');
      expect(await ctl.decline(incoming), 'Pedido recusado.');
      expect(await ctl.cancel(_f('u3')), 'Pedido cancelado.');
      expect(await ctl.unblock(_f('u4')),
          'Desbloqueado. Você pode buscar essa pessoa de novo.');
      expect(await ctl.remove(const Friend(id: 'u5', name: 'Eva')),
          'Amizade removida.');
      expect(social.actions,
          ['accept:u2', 'decline:u2', 'cancel:u3', 'unblock:u4', 'remove:u5']);
    });

    test('relacao que sumiu: Esta amizade nao existe mais', () async {
      final ctl = await setup();
      social.actionOutcome = ActionOutcome.gone;
      expect(await ctl.accept(_f('u2', requester: 'u2')), friendshipGone);
      expect(await ctl.remove(const Friend(id: 'u5', name: 'Eva')),
          friendshipGone);
    });

    test('offline e erro: texto neutro', () async {
      final ctl = await setup();
      social.friendshipError =
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      expect(await ctl.accept(_f('u2', requester: 'u2')), friendOffline);
      social.friendshipError = Exception('x');
      expect(await ctl.decline(_f('u2', requester: 'u2')), friendFailed);
    });
  });

  group('providers derivados', () {
    test('friends, incoming e o selo vem do mesmo stream', () async {
      await setup(relations: [
        _f('a', status: FriendshipStatus.accepted, responderName: 'Ana'),
        _f('b', requester: 'b'),
        _f('c', requester: 'c'),
        _f('d'),
      ]);
      expect(c.read(friendsProvider).valueOrNull!.map((f) => f.name), ['Ana']);
      expect(c.read(incomingRequestCountProvider), 2);
      expect(social.watchFriendshipsCalls, 1);
    });

    test('sem usuario: tudo vazio', () async {
      await setup(loggedIn: false);
      expect(c.read(incomingRequestCountProvider), 0);
      expect(c.read(friendsProvider).valueOrNull, isEmpty);
    });
  });
}
