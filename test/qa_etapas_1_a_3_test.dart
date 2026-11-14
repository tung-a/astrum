// Lacunas de QA para as etapas 1 a 3 (docs/plans/reestruturacao-etapas-1-a-3.md).
// Sem rede: usa apenas os fakes de test/support.
import 'package:astrum/app_router.dart';
import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/models/app_user.dart';
import 'package:astrum/providers/app_providers.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';
import 'support/fake_repositories.dart';

Future<void> settle() => pumpEventQueue();

void main() {
  late FakeRepos repos;
  late FakeFirebaseAuth auth;
  late ProviderContainer container;

  setUp(() {
    repos = FakeRepos();
    auth = FakeFirebaseAuth(FakeUser('u1'));
    container = ProviderContainer(
      overrides: [
        ...repos.overrides,
        firebaseAuthProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    container.listen(eventsProvider, (_, __) {});
    container.listen(friendsProvider, (_, __) {});
    container.listen(intentionProvider, (_, __) {});
    container.listen(profileProvider, (_, __) {});
  });

  // Etapa 2.1 (criterio de horoscopo): o teste existente so mexe em saldo e
  // equipar; aqui o horoscopo diario e o check-in mudam em users/{uid}.
  test('2.1 horoscopo diario e check-in nao reabrem events/friends/intention',
      () async {
    repos.profile.emit(_user());
    await settle();
    expect(repos.events.watchCalls, 1);
    expect(repos.social.watchFriendsCalls, 1);
    expect(repos.social.watchIntentionCalls, 1);

    repos.profile.emit(_user(
      dailyHoroscope: {'date': '2026-11-14', 'content': 'texto'},
      dailyCheckIn: '2026-11-14',
    ));
    await settle();

    expect(repos.events.watchCalls, 1);
    expect(repos.social.watchFriendsCalls, 1);
    expect(repos.social.watchIntentionCalls, 1);
  });

  // Etapa 2.2 (criterio de saldo nao reavaliar redirect), na fonte do
  // refresh: horoscopo e check-in tambem nao devem disparar o router.
  test('2.2 horoscopo nao dispara reavaliacao do router', () async {
    var refreshes = 0;
    container.listen(routerProfileKeyProvider, (_, __) => refreshes++);

    repos.profile.emit(_user());
    await settle();
    final afterFirst = refreshes;

    repos.profile.emit(_user(dailyHoroscope: {'date': 'x', 'content': 'y'}));
    await settle();
    expect(refreshes, afterFirst);
  });

  // Etapa 3.1: o router e o profileProvider compartilham UMA assinatura de
  // authStateChanges (o router usa ref.listen(authStateProvider)).
  testWidgets('3.1 router e perfil compartilham uma unica assinatura de auth',
      (tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SizedBox()),
    ));
    container.read(routerProvider);
    await tester.pump();
    await tester.pump();

    expect(auth.authStateChangesCalls, 1);
  });

  // BUG CANDIDATO (ver docs/qa/etapas-1-a-3.md, BUG-1). Ao trocar de usuario
  // A -> B sem logout, o profileProvider mantem o valor anterior enquanto o
  // perfil de B carrega. Logo o currentUidProvider segue 'a' e os streams de
  // events/friends continuam em A, ate o perfil de B chegar. Esperado: o uid
  // nao deve ser 'a' depois que a auth ja e de B. Remover o skip quando
  // corrigido.
  test(
      'BUG-1 troca A->B sem logout nao mantem o uid de A durante o loading de B',
      () async {
    auth.setUser(FakeUser('a'));
    await settle();
    repos.profile.emit(_user(uid: 'a'));
    await settle();
    expect(container.read(currentUidProvider), 'a');

    auth.setUser(FakeUser('b'));
    await settle();

    // Antes de o perfil de B chegar.
    expect(container.read(currentUidProvider), 'b');
    expect(container.read(routerProfileKeyProvider).isAdmin, isFalse);

    repos.profile.emit(_user(uid: 'b'));
    await settle();
    expect(container.read(currentUidProvider), 'b');
  });
}

AppUser _user({
  String uid = 'u1',
  Map<String, dynamic>? dailyHoroscope,
  String? dailyCheckIn,
}) =>
    AppUser(
      uid: uid,
      email: '$uid@example.com',
      name: 'Teste',
      dailyHoroscope: dailyHoroscope,
      dailyCheckIn: dailyCheckIn,
    );
