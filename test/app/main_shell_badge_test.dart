import 'package:astrum/app/shell/main_shell.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Friendship _incoming(String from) => Friendship(
      id: pairIdOf('u1', from),
      uids: ['u1', from]..sort(),
      requesterUid: from,
      requesterName: 'N$from',
      status: FriendshipStatus.pending,
    );

Future<void> _pump(WidgetTester tester, List<Friendship> list) async {
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
      friendshipsProvider.overrideWith((ref) => Stream.value(list)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('selo no icone do Perfil com a contagem de pedidos recebidos',
      (tester) async {
    await _pump(tester, [_incoming('u2'), _incoming('u3')]);
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.label == '2 pedidos de amizade'),
        findsOneWidget);
    expect(find.byType(Badge), findsOneWidget);
  });

  testWidgets('sem pedidos recebidos nao ha selo', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(Badge), findsNothing);
  });
}
