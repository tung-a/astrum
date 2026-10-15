import 'package:flutter/material.dart';

enum ItemRarity { common, rare, epic, legendary }

enum ItemType { cardSkin, background, profilePicture }

class SkinStyle {
  const SkinStyle({
    required this.colors,
    required this.borderColor,
    required this.iconColor,
  });

  final List<Color> colors;
  final Color borderColor;
  final Color iconColor;
}

class ShopItem {
  const ShopItem({
    required this.id,
    required this.name,
    required this.type,
    required this.rarity,
    required this.price,
    this.description = '',
  });

  final String id;
  final String name;
  final ItemType type;
  final ItemRarity rarity;
  final int price;
  final String description;
}

const cosmeticStyles = <String, SkinStyle>{
  'skin_classic': SkinStyle(
    colors: [Color(0xFF5E35B1), Color(0xFF4527A0)],
    borderColor: Color(0xFFB39DDB),
    iconColor: Color(0x80FFFFFF),
  ),
  'skin_gold': SkinStyle(
    colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
    borderColor: Color(0xFFFFF8E1),
    iconColor: Colors.white,
  ),
  'skin_cyber': SkinStyle(
    colors: [Color(0xFF212121), Color(0xFF000000)],
    borderColor: Color(0xFF00E5FF),
    iconColor: Color(0xFF00E5FF),
  ),
  'skin_dark': SkinStyle(
    colors: [Color(0xFF2B0000), Color(0xFF000000)],
    borderColor: Color(0xFFD50000),
    iconColor: Color(0xFFD50000),
  ),
};

const shopCatalog = <ShopItem>[
  ShopItem(
    id: 'skin_classic',
    name: 'Tarot Clássico',
    type: ItemType.cardSkin,
    rarity: ItemRarity.common,
    price: 0,
    description: 'O véu púrpura original do oráculo.',
  ),
  ShopItem(
    id: 'skin_gold',
    name: 'Alquimia Dourada',
    type: ItemType.cardSkin,
    rarity: ItemRarity.legendary,
    price: 2000,
    description: 'Cartas banhadas em ouro solar.',
  ),
  ShopItem(
    id: 'skin_cyber',
    name: 'Oráculo Cyber',
    type: ItemType.cardSkin,
    rarity: ItemRarity.epic,
    price: 1200,
    description: 'Neon e vazio digital.',
  ),
  ShopItem(
    id: 'skin_dark',
    name: 'Lua Negra',
    type: ItemType.cardSkin,
    rarity: ItemRarity.rare,
    price: 800,
    description: 'O eclipse como manto.',
  ),
  ShopItem(
    id: 'bg_void',
    name: 'Vazio Cósmico',
    type: ItemType.background,
    rarity: ItemRarity.common,
    price: 0,
  ),
  ShopItem(
    id: 'bg_nebula',
    name: 'Nebulosa Roxa',
    type: ItemType.background,
    rarity: ItemRarity.epic,
    price: 1500,
  ),
  ShopItem(
    id: 'bg_temple',
    name: 'Templo Antigo',
    type: ItemType.background,
    rarity: ItemRarity.rare,
    price: 500,
  ),
];

Color rarityColor(ItemRarity rarity) => switch (rarity) {
      ItemRarity.common => const Color(0xFF90A4AE),
      ItemRarity.rare => const Color(0xFF42A5F5),
      ItemRarity.epic => const Color(0xFFAB47BC),
      ItemRarity.legendary => const Color(0xFFFFD54F),
    };

String rarityLabel(ItemRarity rarity) => switch (rarity) {
      ItemRarity.common => 'Comum',
      ItemRarity.rare => 'Raro',
      ItemRarity.epic => 'Épico',
      ItemRarity.legendary => 'Lendário',
    };
