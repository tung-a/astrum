// Testa as transacoes de FirestoreEconomyRepository com fake_cloud_firestore.
// Limitacao do pacote: nao aplica firestore.rules (isso fica em test_rules/) e
// nao simula contencao/retry de transacao; so a logica da transacao e testada.
import 'package:astrum/features/economy/data/economy_repository.dart';
import 'package:astrum/features/economy/domain/economy_exceptions.dart';
import 'package:astrum/features/economy/domain/equip_slot.dart';
import 'package:astrum/features/profile/data/public_profile_sync.dart';
import 'package:astrum/features/profile/domain/public_profile.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_firebase.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreEconomyRepository repo;

  Future<Map<String, dynamic>?> user() async =>
      (await db.collection('users').doc('u1').get()).data();

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = FirestoreEconomyRepository(
      db: db,
      sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth(FakeUser('u1'))),
    );
    await db.collection('users').doc('u1').set({
      'name': 'Luna',
      'email': 'luna@example.com',
      'zodiacSign': 'Aries',
      'wallet': {'stardust': 100},
      'inventory': ['skin_classic', 'bg_void'],
      'equipped': {'skin': 'skin_classic', 'background': 'bg_void'},
    });
    Future<void> item(String id, int price, {bool active = true}) =>
        db.collection('shop_items').doc(id).set({
          'price': price,
          'type': 'skin',
          'rarity': 'common',
          'active': active
        });
    await item('skin_a', 40);
    await item('skin_expensive', 500);
    await item('skin_off', 10, active: false);
  });

  group('purchaseItem', () {
    test('sucesso: debita, acrescenta ao fim do inventario e equipa', () async {
      await repo.purchaseItem(
          uid: 'u1', itemId: 'skin_a', equipSlot: EquipSlot.skin);
      final d = (await user())!;
      expect((d['wallet'] as Map)['stardust'], 60);
      expect(d['inventory'], ['skin_classic', 'bg_void', 'skin_a']);
      expect((d['equipped'] as Map)['skin'], 'skin_a');
    });

    test('sem equipSlot nao altera equipped nem publicProfiles', () async {
      await repo.purchaseItem(uid: 'u1', itemId: 'skin_a');
      final d = (await user())!;
      expect((d['equipped'] as Map)['skin'], 'skin_classic');
      expect((await db.collection('publicProfiles').doc('u1').get()).exists,
          isFalse);
    });

    test('equipar foto de perfil sincroniza publicProfiles', () async {
      await db.collection('shop_items').doc('pfp_a').set({
        'price': 10,
        'type': 'profilePicture',
        'rarity': 'common',
        'active': true
      });
      await repo.purchaseItem(
          uid: 'u1', itemId: 'pfp_a', equipSlot: EquipSlot.profilePicture);
      final pub =
          (await db.collection('publicProfiles').doc('u1').get()).data();
      expect(pub?['avatar'], 'pfp_a');
      expect(pub?['name'], 'Luna');
      expect(pub?['emailHash'], hashEmail('luna@example.com'));
    });

    test('equipar skin nao sincroniza publicProfiles', () async {
      await repo.purchaseItem(
          uid: 'u1', itemId: 'skin_a', equipSlot: EquipSlot.skin);
      expect((await db.collection('publicProfiles').doc('u1').get()).exists,
          isFalse);
    });

    test('saldo insuficiente lanca e nao grava', () async {
      await expectLater(repo.purchaseItem(uid: 'u1', itemId: 'skin_expensive'),
          throwsA(isA<InsufficientFundsException>()));
      final d = (await user())!;
      expect((d['wallet'] as Map)['stardust'], 100);
      expect(d['inventory'], ['skin_classic', 'bg_void']);
    });

    test('item inativo lanca NotPurchasable', () async {
      await expectLater(repo.purchaseItem(uid: 'u1', itemId: 'skin_off'),
          throwsA(isA<NotPurchasableException>()));
      expect(((await user())!['wallet'] as Map)['stardust'], 100);
    });

    test('item inexistente lanca NotPurchasable', () async {
      await expectLater(repo.purchaseItem(uid: 'u1', itemId: 'nao_existe'),
          throwsA(isA<NotPurchasableException>()));
    });

    test('item ja possuido lanca AlreadyOwned e nao cobra', () async {
      await db.collection('shop_items').doc('skin_classic').set(
          {'price': 0, 'type': 'skin', 'rarity': 'common', 'active': true});
      await expectLater(repo.purchaseItem(uid: 'u1', itemId: 'skin_classic'),
          throwsA(isA<AlreadyOwnedException>()));
      final d = (await user())!;
      expect((d['wallet'] as Map)['stardust'], 100);
      expect(d['inventory'], ['skin_classic', 'bg_void']);
    });

    test('perfil inexistente lanca StateError', () async {
      await expectLater(repo.purchaseItem(uid: 'ghost', itemId: 'skin_a'),
          throwsA(isA<StateError>()));
    });
  });

  group('dailyCheckIn', () {
    test('sucesso: credita e grava a data', () async {
      await repo.dailyCheckIn(uid: 'u1', today: '2026-11-14');
      final d = (await user())!;
      expect((d['wallet'] as Map)['stardust'], 125);
      expect(d['dailyCheckIn'], '2026-11-14');
    });

    test('repetido no mesmo dia lanca e nao credita de novo', () async {
      await repo.dailyCheckIn(uid: 'u1', today: '2026-11-14');
      await expectLater(repo.dailyCheckIn(uid: 'u1', today: '2026-11-14'),
          throwsA(isA<AlreadyCheckedInException>()));
      expect(((await user())!['wallet'] as Map)['stardust'], 125);
    });

    test('dia seguinte credita novamente', () async {
      await repo.dailyCheckIn(uid: 'u1', today: '2026-11-14');
      await repo.dailyCheckIn(uid: 'u1', today: '2026-11-15');
      expect(((await user())!['wallet'] as Map)['stardust'], 150);
    });

    test('perfil inexistente lanca StateError', () async {
      await expectLater(repo.dailyCheckIn(uid: 'ghost', today: '2026-11-14'),
          throwsA(isA<StateError>()));
    });
  });
}
