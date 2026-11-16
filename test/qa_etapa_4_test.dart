// Lacunas de QA da etapa 4 (docs/architecture/step4-repositories.md e
// "Itens abertos da etapa 4" em docs/plans/reestruturacao-etapas-1-a-3.md).
// Sem rede: usa fake_cloud_firestore e os fakes de test/support.
//
// Os testes marcados como "caracterizacao" documentam o comportamento ATUAL de
// itens abertos (M3, B1). Quando o usuario decidir a correcao, estes testes
// devem ser atualizados junto com ela.
import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/features/admin/data/admin_repository.dart';
import 'package:astrum/features/economy/data/catalog_repository.dart';
import 'package:astrum/features/economy/data/economy_repository.dart';
import 'package:astrum/features/economy/domain/equip_slot.dart';
import 'package:astrum/features/economy/domain/profile_pictures.dart';
import 'package:astrum/features/economy/presentation/economy_providers.dart';
import 'package:astrum/features/profile/data/profile_repository.dart';
import 'package:astrum/features/profile/data/public_profile_sync.dart';
import 'package:astrum/features/profile/domain/public_profile.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

/// Sync que simula falha de gravacao em publicProfiles (item B1).
class _SyncQueFalha extends PublicProfileSync {
  _SyncQueFalha(FirebaseFirestore db)
      : super(db: db, auth: FakeFirebaseAuth(FakeUser('u1')));

  @override
  Future<void> syncFromUser(String uid) async =>
      throw StateError('falha simulada no publicProfiles');
}

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set({
      'name': 'Luna',
      'email': 'luna@example.com',
      'zodiacSign': 'Aries',
      'wallet': {'stardust': 100},
      'inventory': ['skin_classic', 'bg_void'],
      'equipped': {'skin': 'skin_classic', 'background': 'bg_void'},
    });
  });

  group('compra e cadastro', () {
    test('compra gratuita (preco 0, item novo) nao debita, acrescenta e equipa',
        () async {
      await db.collection('shop_items').doc('skin_free').set(
          {'price': 0, 'type': 'skin', 'rarity': 'common', 'active': true});
      final repo = FirestoreEconomyRepository(
        db: db,
        sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth(FakeUser('u1'))),
      );

      await repo.purchaseItem(
          uid: 'u1', itemId: 'skin_free', equipSlot: EquipSlot.skin);

      final d = (await db.collection('users').doc('u1').get()).data()!;
      expect((d['wallet'] as Map)['stardust'], 100);
      expect(d['inventory'], ['skin_classic', 'bg_void', 'skin_free']);
      expect((d['equipped'] as Map)['skin'], 'skin_free');
    });

    test(
        'createProfile: saldo 500, inventario padrao, pfp zodiacal e publicProfiles',
        () async {
      final repo = FirestoreProfileRepository(
        db: db,
        sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth()),
      );

      await repo.createProfile(
        user: FakeUser('nova', email: 'nova@example.com'),
        name: 'Nova',
        birthDate: '01/01/2000',
        birthTime: '10:00',
        birthPlace: 'Sao Paulo',
        zodiacSign: 'Aries',
      );

      final pfp = defaultProfilePictureId('Aries');
      expect(pfp, isNotEmpty);
      final d = (await db.collection('users').doc('nova').get()).data()!;
      expect((d['wallet'] as Map)['stardust'], 500);
      expect(d['role'], 'user');
      expect(d['inventory'], ['skin_classic', 'bg_void', pfp]);
      expect((d['equipped'] as Map)['profilePicture'], pfp);
      expect((d['preferences'] as Map)['publicProfile'], isTrue);

      final pub =
          (await db.collection('publicProfiles').doc('nova').get()).data()!;
      expect(pub['avatar'], pfp);
      expect(pub['name'], 'Nova');
      expect(pub['emailHash'], hashEmail('nova@example.com'));
    });

    test(
        'B1 (caracterizacao): falha do sync apos compra com foto propaga erro, '
        'mas a compra ja esta gravada', () async {
      await db.collection('shop_items').doc('pfp_a').set({
        'price': 10,
        'type': 'profilePicture',
        'rarity': 'common',
        'active': true,
      });
      final repo = FirestoreEconomyRepository(db: db, sync: _SyncQueFalha(db));

      await expectLater(
        repo.purchaseItem(
            uid: 'u1', itemId: 'pfp_a', equipSlot: EquipSlot.profilePicture),
        throwsA(isA<StateError>()),
      );

      final d = (await db.collection('users').doc('u1').get()).data()!;
      expect((d['wallet'] as Map)['stardust'], 90);
      expect((d['equipped'] as Map)['profilePicture'], 'pfp_a');
    });
  });

  group('perfil publico e LGPD (M3, caracterizacao)', () {
    test(
        'equip(profilePicture) com preferences.publicProfile=false ignora a preferencia e regrava o publicProfiles',
        () async {
      await db.collection('publicProfiles').doc('u1').set({
        'name': 'Luna',
        'avatar': 'pfp_x',
        'emailHash': hashEmail('luna@example.com'),
      });
      final repo = FirestoreProfileRepository(
        db: db,
        sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth()),
      );

      await db
          .collection('users')
          .doc('u1')
          .update({'preferences.publicProfile': false});

      await repo.equip('u1', EquipSlot.profilePicture, 'pfp_y');

      final pub = await db.collection('publicProfiles').doc('u1').get();
      expect(pub.exists, isTrue);
      expect(pub.data()!['avatar'], 'pfp_y');
    });
  });

  group('desvios documentados da etapa 4', () {
    test('desvio 1: syncFromUser usa e-mail do auth quando o perfil nao tem',
        () async {
      await db.collection('users').doc('s').set({
        'name': 'Sem Email',
        'zodiacSign': 'Aries',
      });
      final sync = PublicProfileSync(
        db: db,
        auth: FakeFirebaseAuth(FakeUser('s', email: 'auth@x.com')),
      );

      await sync.syncFromUser('s');
      final pub = (await db.collection('publicProfiles').doc('s').get()).data();
      expect(pub?['emailHash'], hashEmail('auth@x.com'));
    });
  });

  group('leituras sem teste anterior', () {
    test('AdminRepository.listUsers limita a 80 usuarios e le e-mail e nome',
        () async {
      for (var i = 0; i < 85; i++) {
        await db
            .collection('users')
            .doc('x$i')
            .set({'name': 'N$i', 'email': 'n$i@x.com', 'zodiacSign': 'Aries'});
      }

      final list = await AdminRepository(db).listUsers();

      expect(list, hasLength(80));
      final any = list.firstWhere((u) => u.uid.startsWith('x'));
      expect(any.email, endsWith('@x.com'));
      expect(any.name, startsWith('N'));
    });

    test('CatalogRepository.watchShopCatalog mapeia shop_items pelo id',
        () async {
      await db
          .collection('shop_items')
          .doc('skin_a')
          .set({'price': 40, 'type': 'skin', 'rarity': 'rare', 'active': true});
      await db.collection('shop_items').doc('bg_b').set({
        'price': 0,
        'type': 'background',
        'rarity': 'common',
        'active': false,
      });

      final catalog = await CatalogRepository(db).watchShopCatalog().first;

      expect(catalog.keys, unorderedEquals(['skin_a', 'bg_b']));
      expect(catalog['skin_a']!.price, 40);
      expect(catalog['skin_a']!.active, isTrue);
      expect(catalog['bg_b']!.active, isFalse);
    });
  });

  group(
      'risco 3: repositorios reais nao sao recriados a cada mudanca de perfil',
      () {
    test(
        'eventsRepositoryProvider e economyRepositoryProvider mantem a instancia '
        'ao trocar de usuario', () async {
      final auth = FakeFirebaseAuth(FakeUser('u1'));
      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(auth),
      ]);
      addTearDown(container.dispose);
      container.listen(profileProvider, (_, __) {});
      container.listen(eventsProvider, (_, __) {});
      await pumpEventQueue();

      final events = container.read(eventsRepositoryProvider);
      final economy = container.read(economyRepositoryProvider);

      auth.setUser(FakeUser('u2'));
      await pumpEventQueue();
      auth.setUser(null);
      await pumpEventQueue();

      expect(
          identical(container.read(eventsRepositoryProvider), events), isTrue);
      expect(identical(container.read(economyRepositoryProvider), economy),
          isTrue);
    });
  });
}
