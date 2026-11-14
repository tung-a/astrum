import 'package:astrum/core/astro/zodiac.dart';
import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/models/shop_item.dart';
import 'package:astrum/data/profile_pictures.dart';

const _baseShopCatalog = <ShopItem>[
  ShopItem(
    id: defaultSkinId,
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
    id: defaultBackgroundId,
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

final profilePictureShopCatalog = [
  for (final sign in zodiacSigns)
    for (final variant in profilePictureVariants)
      ShopItem(
        id: 'pfp_${zodiacSlug(sign)}_${variant.key}',
        name: 'Avatar $sign · ${variant.label}',
        type: ItemType.profilePicture,
        rarity: variant.rarity,
        price: variant.price,
        description: 'Um avatar astral inspirado em $sign.',
      ),
];

final shopCatalog = [..._baseShopCatalog, ...profilePictureShopCatalog];

/// Todos os itens visuais, incluindo os avatares gratuitos de essencia
/// zodiacal. O preco aqui e so o valor de seed: a fonte de verdade do preco e
/// o catalogo shop_items no Firestore.
final fullShopCatalog = [
  ...shopCatalog,
  for (final sign in zodiacSigns)
    ShopItem(
      id: defaultProfilePictureId(sign),
      name: 'Avatar $sign · Essência Zodiacal',
      type: ItemType.profilePicture,
      rarity: ItemRarity.common,
      price: 0,
    ),
];
