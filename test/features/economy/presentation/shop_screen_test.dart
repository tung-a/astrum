import 'package:astrum/features/economy/domain/catalog_entry.dart';
import 'package:astrum/features/economy/domain/economy_exceptions.dart';
import 'package:astrum/features/economy/presentation/economy_providers.dart';
import 'package:astrum/features/economy/presentation/shop_screen.dart';
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
}
