import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/features/economy/domain/catalog_entry.dart';
import 'package:astrum/features/economy/domain/economy_exceptions.dart';
import 'package:astrum/features/economy/domain/equip_slot.dart';
import 'package:astrum/features/economy/presentation/economy_providers.dart';
import 'package:astrum/features/economy/presentation/shop_screen.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/pump_screen.dart';

void main() {
  testWidgets('Comprar chama a economia e mostra o erro de saldo',
      (tester) async {
    final economy = FakeEconomyRepository()
      ..purchaseError = const InsufficientFundsException();
    await pumpScreen(
      tester,
      const ShopScreen(),
      user: testUser(),
      overrides: [
        economyRepositoryProvider.overrideWithValue(economy),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
        shopCatalogProvider.overrideWith((ref) => Stream.value({
              'skin_gold': const CatalogEntry(
                  price: 2000, type: 'skin', rarity: 'legendary', active: true),
            })),
      ],
    );

    expect(find.text('Comprar'), findsOneWidget);
    await tester.tap(find.text('Comprar'));
    await tester.pump();
    await tester.pump();

    expect(economy.purchases, hasLength(1));
    expect(economy.purchases.single.itemId, 'skin_gold');
    expect(find.text('Poeira Estelar insuficiente.'), findsOneWidget);
  });

  testWidgets('item ja possuido mostra Equipar, grava o slot e nao cobra',
      (tester) async {
    final economy = FakeEconomyRepository();
    final profiles = FakeProfileRepository();
    await pumpScreen(
      tester,
      const ShopScreen(),
      user: AppUser(
        uid: 'u1',
        email: 'u1@example.com',
        name: 'Teste',
        stardust: 500,
        inventory: [...defaultInventory, 'skin_gold'],
      ),
      overrides: [
        economyRepositoryProvider.overrideWithValue(economy),
        profileRepositoryProvider.overrideWithValue(profiles),
        shopCatalogProvider.overrideWith((ref) => Stream.value({
              'skin_gold': const CatalogEntry(
                  price: 2000, type: 'skin', rarity: 'legendary', active: true),
            })),
      ],
    );

    expect(find.text('Comprar'), findsNothing);
    await tester.tap(find.text('Equipar'));
    await tester.pump();
    await tester.pump();

    expect(economy.purchases, isEmpty);
    expect(profiles.equips.single.uid, 'u1');
    expect(profiles.equips.single.slot, EquipSlot.skin);
    expect(profiles.equips.single.itemId, 'skin_gold');
    expect(find.text('Poeira Estelar insuficiente.'), findsNothing);
  });
}
