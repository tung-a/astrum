import 'dart:convert';

import 'package:astrum/core/astro/natal_chart.dart';
import 'package:astrum/features/economy/domain/equip_slot.dart';
import 'package:astrum/features/economy/domain/equip_slot_field.dart';
import 'package:astrum/features/economy/domain/shop_item.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ItemType.slot mapeia para o EquipSlot e o fieldPath esperados', () {
    expect(ItemType.cardSkin.slot, EquipSlot.skin);
    expect(ItemType.cardSkin.slot.fieldPath, 'equipped.skin');
    expect(ItemType.background.slot, EquipSlot.background);
    expect(ItemType.background.slot.fieldPath, 'equipped.background');
    expect(ItemType.profilePicture.slot, EquipSlot.profilePicture);
    expect(ItemType.profilePicture.slot.fieldPath, 'equipped.profilePicture');
  });

  test('fieldPath igual aos literais gravados no Firestore', () {
    expect(EquipSlot.skin.fieldPath, 'equipped.skin');
    expect(EquipSlot.background.fieldPath, 'equipped.background');
    expect(EquipSlot.profilePicture.fieldPath, 'equipped.profilePicture');
  });

  test('so profilePicture toca o perfil publico', () {
    expect(EquipSlot.values.where((s) => s.touchesPublicProfile),
        [EquipSlot.profilePicture]);
  });

  test('todo ItemType mapeia para um slot distinto', () {
    final slots = ItemType.values.map((t) => t.slot).toSet();
    expect(slots.length, ItemType.values.length);
    expect(ItemType.cardSkin.slot, EquipSlot.skin);
    expect(ItemType.background.slot, EquipSlot.background);
    expect(ItemType.profilePicture.slot, EquipSlot.profilePicture);
  });

  test('encodeAstralMap faz round-trip com parseAstralMap', () {
    const chart = [
      PlanetPosition(
          planet: 'Sol',
          sign: 'Aries',
          house: '1',
          element: 'Fogo',
          summary: 's'),
      PlanetPosition(
          planet: 'Lua',
          sign: 'Touro',
          house: '2',
          element: 'Terra',
          summary: 'l'),
    ];
    final back = AppUser.parseAstralMap(AppUser.encodeAstralMap(chart));
    expect(back.map((e) => e.toJson()), chart.map((e) => e.toJson()));
  });

  test('encodeAstralMap lanca StateError em lista vazia', () {
    expect(() => AppUser.encodeAstralMap(const []), throwsStateError);
  });

  test('encodeAstralMap gera o mesmo texto do jsonEncode antigo da tela', () {
    const chart = [
      PlanetPosition(
          planet: 'Sol',
          sign: 'Aries',
          house: '1',
          element: 'Fogo',
          summary: 's'),
    ];
    expect(AppUser.encodeAstralMap(chart),
        jsonEncode(chart.map((e) => e.toJson()).toList()));
  });
}
