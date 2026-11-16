import 'dart:async';

import 'package:astrum/features/social/data/social_repository.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/presentation/friend_requests_screen.dart';
import 'package:astrum/features/social/presentation/friendship_controller.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/make_container.dart';
import '../../../support/pump_screen.dart';

/// Repositorio real cuja escrita simples nunca completa (SDK offline: a
/// escrita fica na fila local e a Future espera o servidor).
class _HangingRepo extends SocialRepository {
  _HangingRepo(Duration timeout)
      : super(FakeFirebaseFirestore(), writeTimeout: timeout);

  final never = Completer<Never>();
  int calls = 0;

  @override
  Future<T> runGuarded<T>(Future<T> Function() op) {
    calls++;
    return never.future.then((_) => throw StateError('inalcancavel'));
  }
}

Friendship _f(String other,
        {String requester = 'u1',
        FriendshipStatus status = FriendshipStatus.pending,
        String? responderName,
        String? declinedBy}) =>
    Friendship(
      id: pairIdOf('u1', other),
      uids: ['u1', other]..sort(),
      requesterUid: requester,
      requesterName: 'Nome $other',
      status: status,
      responderName: responderName,
      declinedBy: declinedBy,
    );

void main() {
  group('controller: escrita que nunca completa vira "Sem conexao"', () {
    late _HangingRepo repo;
    late FriendshipController ctl;

    setUp(() async {
      repo = _HangingRepo(const Duration(milliseconds: 20));
      final c = await makeContainer(
        user: testUser(),
        overrides: [socialRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      c.listen(friendshipsViewProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      ctl = c.read(friendshipControllerProvider.notifier);
    });

    test('aceitar', () async {
      expect(await ctl.accept(_f('u2', requester: 'u2')), friendOffline);
      expect(repo.calls, 1);
    });

    test('recusar', () async {
      expect(await ctl.decline(_f('u2', requester: 'u2')), friendOffline);
    });

    test('remover', () async {
      expect(await ctl.remove(const Friend(id: 'u2', name: 'Nome')),
          friendOffline);
    });

    test('cancelar', () async {
      expect(await ctl.cancel(_f('u2')), friendOffline);
    });

    test('desbloquear', () async {
      final lapide =
          _f('u2', status: FriendshipStatus.declined, declinedBy: 'u1');
      expect(await ctl.unblock(lapide), friendOffline);
    });
  });

  group('tela: botao e solto e a mensagem aparece', () {
    late _HangingRepo repo;

    Future<void> open(WidgetTester tester, List<Friendship> l) {
      repo = _HangingRepo(const Duration(seconds: 1));
      return pumpScreen(tester, const FriendRequestsScreen(),
          user: testUser(),
          overrides: [
            socialRepositoryProvider.overrideWithValue(repo),
            friendshipsProvider.overrideWith((ref) => Stream.value(l)),
          ]);
    }

    bool enabled(WidgetTester tester, String label) =>
        tester
            .widget<ButtonStyleButton>(find.ancestor(
                of: find.text(label),
                matching:
                    find.byWidgetPredicate((w) => w is ButtonStyleButton)))
            .onPressed !=
        null;

    Future<void> run(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pump();
      expect(enabled(tester, label), isFalse,
          reason: 'ocupado enquanto espera');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(friendOffline), findsOneWidget);
      expect(enabled(tester, label), isTrue, reason: 'botao solto');
    }

    testWidgets('aceitar', (tester) async {
      await open(tester, [_f('u2', requester: 'u2')]);
      await run(tester, 'Aceitar');
    });

    testWidgets('recusar', (tester) async {
      await open(tester, [_f('u2', requester: 'u2')]);
      await run(tester, 'Recusar');
    });

    testWidgets('cancelar pedido', (tester) async {
      await open(tester, [_f('u3')]);
      await run(tester, 'Cancelar pedido');
    });

    testWidgets('desbloquear', (tester) async {
      await open(tester, [
        _f('u5', status: FriendshipStatus.declined, declinedBy: 'u1'),
      ]);
      await run(tester, 'Desbloquear');
    });
  });
}
