import 'dart:async';

import 'package:astrum/app/shell/main_shell.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Complementa main_shell_badge_test.dart: rotulo no singular, pedido que eu
/// enviei nao conta no selo e o selo some quando o pedido e aceito (o stream
/// atualiza a tela sem recarregar).

Friendship _incoming(String from) => Friendship(
      id: pairIdOf('u1', from),
      uids: ['u1', from]..sort(),
      requesterUid: from,
      requesterName: 'N$from',
      status: FriendshipStatus.pending,
    );

Friendship _outgoing(String to) => Friendship(
      id: pairIdOf('u1', to),
      uids: ['u1', to]..sort(),
      requesterUid: 'u1',
      requesterName: 'Teste',
      status: FriendshipStatus.pending,
    );

Friendship _accepted(String other) => Friendship(
      id: pairIdOf('u1', other),
      uids: ['u1', other]..sort(),
      requesterUid: other,
      requesterName: 'N$other',
      status: FriendshipStatus.accepted,
      responderName: 'Teste',
    );

Future<void> _pump(WidgetTester tester, Stream<List<Friendship>> stream) async {
  final router = GoRouter(
    initialLocation: '/a',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => MainShell(navigationShell: shell),
        branches: [
          for (final p in ['/a', '/b', '/c', '/d', '/e'])
            StatefulShellBranch(routes: [
              GoRoute(path: p, builder: (_, __) => const SizedBox()),
            ]),
        ],
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue('u1'),
      friendshipsProvider.overrideWith((ref) => stream),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _selo(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label);

void main() {
  testWidgets('um pedido recebido: rotulo no singular', (tester) async {
    await _pump(tester, Stream.value([_incoming('u2')]));
    expect(_selo('1 pedido de amizade'), findsOneWidget);
    expect(find.byType(Badge), findsOneWidget);
  });

  testWidgets('pedido que eu enviei nao conta no selo', (tester) async {
    await _pump(tester, Stream.value([_outgoing('u3')]));
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('selo some quando o pedido recebido e aceito (stream atualiza)',
      (tester) async {
    final ctl = StreamController<List<Friendship>>.broadcast();
    addTearDown(ctl.close);
    await _pump(tester, ctl.stream);

    ctl.add([_incoming('u2')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_selo('1 pedido de amizade'), findsOneWidget);

    ctl.add([_accepted('u2')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(Badge), findsNothing);
  });
}
