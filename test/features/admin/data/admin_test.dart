// ignore_for_file: subtype_of_sealed_class

import 'package:astrum/features/admin/data/admin_repository.dart';
import 'package:astrum/features/admin/data/crystal_seed.dart';
import 'package:astrum/features/economy/domain/catalog_seed.dart';
import 'package:astrum/features/economy/domain/shop_item.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = ShopItem(
    id: 'a',
    name: 'A',
    type: ItemType.cardSkin,
    rarity: ItemRarity.rare,
    price: 100);
const _b = ShopItem(
    id: 'b',
    name: 'B',
    type: ItemType.background,
    rarity: ItemRarity.common,
    price: 50);

/// Db cuja leitura de shop_items falha; qualquer batch e registrado.
class _DbLeituraFalha implements FirebaseFirestore {
  int batchCalls = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _ColFalha();

  @override
  WriteBatch batch() {
    batchCalls++;
    throw StateError('batch nao deveria ser criado');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _ColFalha implements CollectionReference<Map<String, dynamic>> {
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      throw FirebaseException(plugin: 'firestore', message: 'sem permissao');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  group('planCatalogPublish', () {
    test(
        'novo recebe price e active; existente so type e rarity; fora do seed '
        'so active:false; nunca remove', () {
      final plan =
          planCatalogPublish(existingIds: {'a', 'velho'}, seed: const [_a, _b]);
      expect(plan['a'], {'type': 'skin', 'rarity': 'rare'});
      expect(plan['b'], {
        'type': 'background',
        'rarity': 'common',
        'price': 50,
        'active': true
      });
      expect(plan['velho'], {'active': false});
      expect(plan.keys.toSet(), {'a', 'b', 'velho'});
    });

    test('catalogo completo cabe em um batch (< 500)', () {
      final plan = planCatalogPublish(existingIds: {}, seed: fullShopCatalog);
      expect(plan.length, lessThan(500));
    });
  });

  group('AdminRepository (Firestore fake)', () {
    test('publishCatalog preserva price e active de existentes', () async {
      final db = FakeFirebaseFirestore();
      await db
          .collection('shop_items')
          .doc('a')
          .set({'price': 999, 'active': false, 'type': 'x', 'rarity': 'y'});
      await db.collection('shop_items').doc('velho').set({'active': true});

      await AdminRepository(db).publishCatalog(const [_a, _b]);

      final a = (await db.collection('shop_items').doc('a').get()).data()!;
      expect(a['price'], 999);
      expect(a['active'], false);
      expect(a['type'], 'skin');
      final b = (await db.collection('shop_items').doc('b').get()).data()!;
      expect(b['price'], 50);
      expect(b['active'], true);
      final v = (await db.collection('shop_items').doc('velho').get()).data()!;
      expect(v['active'], false);
    });

    test('falha na leitura nao grava e vira AdminOperationException', () async {
      final db = _DbLeituraFalha();
      await expectLater(
          AdminRepository(db).publishCatalog(const [_a]),
          throwsA(isA<AdminOperationException>()
              .having((e) => e.message, 'message', 'sem permissao')));
      expect(db.batchCalls, 0);
    });

    test('seedCrystals grava os cristais', () async {
      final db = FakeFirebaseFirestore();
      await AdminRepository(db).seedCrystals();
      final snap = await db.collection('cristais_propriedades').get();
      expect(snap.docs.length, initialCrystals.length);
      final d =
          (await db.collection('cristais_propriedades').doc('citrino').get())
              .data()!;
      expect(d['nome'], 'Citrino - Prosperidade');
      expect(d['foco'], 'Carreira/Finanças');
      expect(d.keys.toSet(), {'nome', 'descricao', 'foco'});
    });

    test('watchAnalyticsEvents filtra por since, ordena desc e limita a 500',
        () async {
      final db = FakeFirebaseFirestore();
      final base = DateTime(2026, 1, 10);
      Future<void> ev(String id, DateTime t, String u, String n) =>
          db.collection('analytics_events').doc(id).set({
            'createdAt': Timestamp.fromDate(t),
            'userId': u,
            'eventName': n
          });
      await ev('velho', base.subtract(const Duration(days: 5)), 'u0', 'old');
      await ev('e1', base.add(const Duration(hours: 1)), 'u1', 'login');
      await ev('e2', base.add(const Duration(hours: 3)), 'u2', 'sign_up');
      await ev('e3', base.add(const Duration(hours: 2)), 'u1', 'login');

      final rows =
          await AdminRepository(db).watchAnalyticsEvents(since: base).first;

      expect(
          rows.map((r) => r.eventName).toList(), ['sign_up', 'login', 'login']);
      expect(rows.map((r) => r.userId).toList(), ['u2', 'u1', 'u1']);

      for (var i = 0; i < 510; i++) {
        await ev('m$i', base.add(Duration(minutes: i)), 'u', 'x');
      }
      final many =
          await AdminRepository(db).watchAnalyticsEvents(since: base).first;
      expect(many.length, 500);
    });
  });

  test('watchAnalyticsEvents: userId/eventName nao-string viram null',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('analytics_events').doc('x').set({
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 10)),
      'userId': 123,
      'eventName': 'login',
    });
    final rows = await AdminRepository(db)
        .watchAnalyticsEvents(since: DateTime(2026, 1, 1))
        .first;
    expect(rows.single.userId, isNull);
    expect(rows.single.eventName, 'login');
  });

  group('summarizeAnalytics', () {
    test('exclui anonymous dos usuarios unicos, ignora eventName vazio e conta',
        () {
      final s = summarizeAnalytics([
        (userId: 'u1', eventName: 'login'),
        (userId: 'u1', eventName: 'login'),
        (userId: 'anonymous', eventName: 'view'),
        (userId: null, eventName: 'view'),
        (userId: 'u2', eventName: ''),
        (userId: 'u3', eventName: null),
      ]);
      expect(s.total, 6);
      expect(s.uniqueUsers, 3);
      expect(s.counts, {'login': 2, 'view': 2});
    });
  });

  test('AdminOperationException leva a mensagem original', () {
    expect(const AdminOperationException('x').message, 'x');
  });
}
