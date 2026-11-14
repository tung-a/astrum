import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

void main() {
  test('ProfileRepository e profileProvider usam as instancias sobrescritas',
      () async {
    final auth = FakeFirebaseAuth(FakeUser('u1', email: 'x@y.z'));
    final db = FakeFirestore()
      ..docs['users/u1'] = {
        'name': 'Luna',
        'wallet': {'stardust': 123},
      };
    final container = ProviderContainer(overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      firestoreProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    container.listen(profileProvider, (_, __) {});

    auth.setUser(FakeUser('u1', email: 'x@y.z'));
    await pumpEventQueue();

    final user = container.read(profileProvider).valueOrNull;
    expect(user?.name, 'Luna');
    expect(user?.stardust, 123);
    expect(db.docPaths, contains('users/u1'));
  });

  test('AnalyticsService usa Firestore e Auth sobrescritos', () async {
    final auth = FakeFirebaseAuth(FakeUser('u9'));
    final db = FakeFirestore();
    final container = ProviderContainer(overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      firestoreProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    await container.read(analyticsServiceProvider).logEvent('login');

    expect(db.added, hasLength(1));
    expect(db.added.single.$1, 'analytics_events');
    expect(db.added.single.$2['userId'], 'u9');
    expect(db.added.single.$2['eventName'], 'login');
  });

  test('authStateProvider deriva de firebaseAuthProvider', () async {
    final auth = FakeFirebaseAuth();
    final container = ProviderContainer(
      overrides: [firebaseAuthProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);
    container.listen(authStateProvider, (_, __) {});

    auth.setUser(FakeUser('z'));
    await pumpEventQueue();

    expect(container.read(authStateProvider).valueOrNull?.uid, 'z');
    expect(auth.authStateChangesCalls, 1);
  });
}
