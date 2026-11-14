import 'package:astrum/app_router.dart';
import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/providers/app_providers.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
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
    // Mantem os providers vivos, como as telas fariam.
    container.listen(eventsProvider, (_, __) {});
    container.listen(friendsProvider, (_, __) {});
    container.listen(intentionProvider, (_, __) {});
    // Faz o profileProvider assinar o stream antes do primeiro emit.
    container.listen(profileProvider, (_, __) {});
  });

  test('saldo, equipar e horoscopo nao reabrem events/friends/intention',
      () async {
    repos.profile.emit(testUser());
    await settle();
    expect(repos.events.watchCalls, 1);
    expect(repos.social.watchFriendsCalls, 1);
    expect(repos.social.watchIntentionCalls, 1);

    repos.profile.emit(testUser(stardust: 475));
    await settle();
    repos.profile.emit(testUser(stardust: 475, equippedSkin: 'skin_x'));
    await settle();

    expect(repos.events.watchCalls, 1);
    expect(repos.social.watchFriendsCalls, 1);
    expect(repos.social.watchIntentionCalls, 1);
  });

  test('notificationsEnabled reabre apenas a intencao', () async {
    repos.profile.emit(testUser());
    await settle();
    expect(repos.social.watchIntentionCalls, 1);

    repos.profile.emit(testUser(notificationsEnabled: false));
    await settle();
    // Desligado: nao assina.
    expect(repos.social.watchIntentionCalls, 1);

    repos.profile.emit(testUser(notificationsEnabled: true));
    await settle();
    expect(repos.social.watchIntentionCalls, 2);
    expect(repos.events.watchCalls, 1);
    expect(repos.social.watchFriendsCalls, 1);
  });

  test('troca de uid recria os streams para o novo usuario', () async {
    auth.setUser(FakeUser('a'));
    await settle();
    repos.profile.emit(testUser(uid: 'a'));
    await settle();
    auth.setUser(FakeUser('b'));
    await settle();
    repos.profile.emit(testUser(uid: 'b'));
    await settle();

    expect(repos.events.uids, ['a', 'b']);
    expect(repos.social.watchFriendsCalls, 2);
    expect(repos.social.watchIntentionCalls, 2);
  });

  test('login A, logout, login B: perfil e uid passam a ser de B e A e cancelado',
      () async {
    auth.setUser(FakeUser('a'));
    await settle();
    repos.profile.emit(testUser(uid: 'a', role: 'admin'));
    await settle();
    expect(container.read(currentUidProvider), 'a');
    expect(container.read(profileProvider).valueOrNull?.isAdmin, isTrue);
    expect(repos.profile.activeProfileListeners, {'a'});

    auth.setUser(null);
    await settle();
    expect(container.read(profileProvider).valueOrNull, isNull);
    expect(container.read(currentUidProvider), isNull);
    expect(repos.profile.activeProfileListeners, isEmpty);

    auth.setUser(FakeUser('b'));
    await settle();
    repos.profile.emit(testUser(uid: 'b'));
    await settle();
    expect(container.read(currentUidProvider), 'b');
    expect(container.read(profileProvider).valueOrNull?.isAdmin, isFalse);
    expect(repos.profile.activeProfileListeners, {'b'});
    expect(repos.profile.profileWatchedUids, ['a', 'b']);
    expect(repos.events.uids.last, 'b');
    // Uma unica assinatura de authStateChanges para o app.
    expect(auth.authStateChangesCalls, 1);
  });

  test('erro no stream de auth deixa o perfil nulo (deslogado)', () async {
    repos.profile.emit(testUser());
    await settle();
    expect(container.read(currentUidProvider), 'u1');

    auth.setError(Exception('falha'));
    await settle();
    expect(container.read(profileProvider).valueOrNull, isNull);
    expect(container.read(currentUidProvider), isNull);
    expect(repos.profile.activeProfileListeners, isEmpty);
  });

  group('routerProfileKeyProvider', () {
    test('saldo nao dispara reavaliacao; isAdmin dispara', () async {
      var refreshes = 0;
      container.listen(routerProfileKeyProvider, (_, __) => refreshes++);

      repos.profile.emit(testUser());
      await settle();
      final afterFirst = refreshes; // loading -> data
      expect(afterFirst, greaterThan(0));

      repos.profile.emit(testUser(stardust: 100));
      await settle();
      expect(refreshes, afterFirst);

      repos.profile.emit(testUser(stardust: 100, role: 'admin'));
      await settle();
      expect(refreshes, afterFirst + 1);
      expect(container.read(routerProfileKeyProvider).isAdmin, isTrue);
    });
  });

  group('decideRedirect', () {
    String? r(String loc,
            {bool loggedIn = true, bool admin = false, bool loading = false}) =>
        decideRedirect(
            loggedIn: loggedIn,
            location: loc,
            isAdmin: admin,
            isLoading: loading);

    test('nao logado em rota protegida vai para login', () {
      expect(r('/app/cosmos', loggedIn: false), '/login');
      expect(r('/login', loggedIn: false), isNull);
    });
    test('logado em /login vai para home (ou admin)', () {
      expect(r('/login'), '/app/cosmos');
      expect(r('/login', admin: true), '/admin');
      expect(r('/login', loading: true), isNull);
    });
    test('/admin exige admin; carregando aguarda', () {
      expect(r('/admin'), '/app/account');
      expect(r('/admin', loading: true), isNull);
      expect(r('/admin', admin: true), isNull);
    });
    test('admin e levado de /app/* para /admin', () {
      expect(r('/app/cosmos', admin: true), '/admin');
    });
  });
}
