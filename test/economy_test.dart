import 'package:astrum/services/economy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computePurchase', () {
    test('debita o preco e mantem itens antigos', () {
      final r = computePurchase(
        stardust: 500,
        inventory: ['skin_classic', 'bg_void'],
        itemId: 'skin_x',
        price: 200,
      );
      expect(r.stardust, 300);
      expect(r.inventory, ['skin_classic', 'bg_void', 'skin_x']);
    });

    test('saldo exato zera sem ficar negativo', () {
      final r = computePurchase(
          stardust: 500, inventory: [], itemId: 'a', price: 500);
      expect(r.stardust, 0);
    });

    test('saldo insuficiente', () {
      expect(
        () => computePurchase(
            stardust: 499, inventory: [], itemId: 'a', price: 500),
        throwsA(isA<InsufficientFundsException>()),
      );
    });

    test('item ja possuido (segundo toque) falha sem cobrar', () {
      final first = computePurchase(
          stardust: 1000, inventory: ['x'], itemId: 'a', price: 100);
      expect(
        () => computePurchase(
            stardust: first.stardust,
            inventory: first.inventory,
            itemId: 'a',
            price: 100),
        throwsA(isA<AlreadyOwnedException>()),
      );
    });

    test('preco zero adiciona o item sem mexer no saldo', () {
      final r = computePurchase(
          stardust: 10, inventory: [], itemId: 'a', price: 0);
      expect(r.stardust, 10);
      expect(r.inventory, ['a']);
    });

    test('preco negativo nao e compravel', () {
      expect(
        () => computePurchase(
            stardust: 10, inventory: [], itemId: 'a', price: -5),
        throwsA(isA<NotPurchasableException>()),
      );
    });
  });

  group('resolvePrice', () {
    const entry =
        CatalogEntry(price: 800, type: 'skin', rarity: 'rare', active: true);

    test('usa o preco do catalogo', () {
      expect(resolvePrice({'a': entry}, 'a'), 800);
    });

    test('catalogo vazio: indisponivel', () {
      expect(() => resolvePrice({}, 'a'),
          throwsA(isA<CatalogUnavailableException>()));
    });

    test('item fora do catalogo ou inativo nao e compravel', () {
      expect(() => resolvePrice({'a': entry}, 'b'),
          throwsA(isA<NotPurchasableException>()));
      const off =
          CatalogEntry(price: 1, type: 'skin', rarity: 'rare', active: false);
      expect(() => resolvePrice({'a': off}, 'a'),
          throwsA(isA<NotPurchasableException>()));
    });

    test('doc sem preco vira invalido', () {
      final e = CatalogEntry.fromMap({'active': true});
      expect(() => resolvePrice({'a': e}, 'a'),
          throwsA(isA<NotPurchasableException>()));
    });
  });

  group('computeCheckIn', () {
    test('primeiro check-in credita 25', () {
      expect(
          computeCheckIn(
              stardust: 100, lastCheckIn: null, today: '2026-11-08'),
          125);
    });

    test('mesmo dia nao credita', () {
      expect(
        () => computeCheckIn(
            stardust: 100, lastCheckIn: '2026-11-08', today: '2026-11-08'),
        throwsA(isA<AlreadyCheckedInException>()),
      );
    });

    test('dia seguinte credita', () {
      expect(
          computeCheckIn(
              stardust: 100, lastCheckIn: '2026-11-08', today: '2026-11-09'),
          125);
    });

    test('data gravada no futuro nao credita', () {
      expect(
        () => computeCheckIn(
            stardust: 100, lastCheckIn: '2026-11-09', today: '2026-11-08'),
        throwsA(isA<AlreadyCheckedInException>()),
      );
    });
  });
}
