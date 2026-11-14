import 'package:astrum/features/economy/domain/economy_exceptions.dart';
import 'package:astrum/features/economy/domain/equip_slot.dart';
import 'package:astrum/features/economy/domain/shop_item.dart';
import 'package:astrum/features/economy/presentation/economy_providers.dart';
import 'package:astrum/features/economy/presentation/shop_controller.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/make_container.dart';

const _owned = ShopItem(
    id: 'skin_classic',
    name: 'Tarot Classico',
    type: ItemType.cardSkin,
    rarity: ItemRarity.common,
    price: 0);
const _toBuy = ShopItem(
    id: 'skin_gold',
    name: 'Alquimia',
    type: ItemType.cardSkin,
    rarity: ItemRarity.legendary,
    price: 2000);

void main() {
  late FakeProfileRepository profileRepo;
  late FakeEconomyRepository economy;

  setUp(() {
    profileRepo = FakeProfileRepository();
    economy = FakeEconomyRepository();
  });

  Future<ProviderContainer> setup() async {
    final c = await makeContainer(user: testUser(), overrides: [
      profileRepositoryProvider.overrideWithValue(profileRepo),
      economyRepositoryProvider.overrideWithValue(economy),
    ]);
    addTearDown(c.dispose);
    // Mantem o autoDispose vivo.
    c.listen(shopControllerProvider, (_, __) {});
    return c;
  }

  test('item do inventario: equipa no slot e nao compra', () async {
    final c = await setup();

    final msg =
        await c.read(shopControllerProvider.notifier).selectItem(_owned);

    expect(msg, isNull);
    expect(profileRepo.equips,
        [(uid: 'u1', slot: EquipSlot.skin, itemId: 'skin_classic')]);
    expect(economy.purchases, isEmpty);
  });

  test('item fora do inventario: compra e equipa na mesma gravacao', () async {
    final c = await setup();

    final msg =
        await c.read(shopControllerProvider.notifier).selectItem(_toBuy);

    expect(msg, isNull);
    expect(economy.purchases,
        [(uid: 'u1', itemId: 'skin_gold', equipSlot: EquipSlot.skin)]);
    expect(profileRepo.equips, isEmpty);
  });

  test('erro de economia vira a mensagem da excecao', () async {
    final c = await setup();
    economy.purchaseError = const InsufficientFundsException();

    final msg =
        await c.read(shopControllerProvider.notifier).selectItem(_toBuy);

    expect(msg, 'Poeira Estelar insuficiente.');
    expect(c.read(shopControllerProvider).buying, isFalse);
  });

  test('erro generico vira a mensagem padrao', () async {
    final c = await setup();
    economy.purchaseError = StateError('boom');

    final msg =
        await c.read(shopControllerProvider.notifier).selectItem(_toBuy);

    expect(msg, 'Não foi possível concluir. Tente novamente.');
    expect(c.read(shopControllerProvider).buying, isFalse);
  });

  test('erro ao equipar tambem cai na mensagem padrao', () async {
    final c = await setup();
    profileRepo.equipError = StateError('boom');

    final msg =
        await c.read(shopControllerProvider.notifier).selectItem(_owned);

    expect(msg, 'Não foi possível concluir. Tente novamente.');
  });

  test('buying fica true durante a compra e duplo toque e ignorado', () async {
    final c = await setup();
    final ctl = c.read(shopControllerProvider.notifier);

    final first = ctl.selectItem(_toBuy);
    expect(c.read(shopControllerProvider).buying, isTrue);
    final second = await ctl.selectItem(_toBuy);
    await first;

    expect(second, isNull);
    expect(economy.purchases, hasLength(1));
    expect(c.read(shopControllerProvider).buying, isFalse);
  });

  test('sem perfil nao faz nada', () async {
    final c = await makeContainer(overrides: [
      profileRepositoryProvider.overrideWithValue(profileRepo),
      economyRepositoryProvider.overrideWithValue(economy),
    ]);
    addTearDown(c.dispose);
    c.listen(shopControllerProvider, (_, __) {});

    final msg =
        await c.read(shopControllerProvider.notifier).selectItem(_toBuy);

    expect(msg, isNull);
    expect(economy.purchases, isEmpty);
    expect(profileRepo.equips, isEmpty);
  });

  test('descartado durante a compra: termina sem lancar', () async {
    final c = await setup();
    final ctl = c.read(shopControllerProvider.notifier);
    final future = ctl.selectItem(_toBuy);
    c.invalidate(shopControllerProvider);
    await c.pump();

    expect(await future, isNull);
  });

  test('equip (inventario) grava no slot e propaga o erro', () async {
    final c = await setup();
    final ctl = c.read(shopControllerProvider.notifier);

    await ctl.equip(_owned);
    expect(profileRepo.equips,
        [(uid: 'u1', slot: EquipSlot.skin, itemId: 'skin_classic')]);

    profileRepo.equipError = StateError('boom');
    await expectLater(ctl.equip(_owned), throwsStateError);
  });
}
