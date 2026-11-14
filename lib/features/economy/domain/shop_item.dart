import 'package:astrum/features/economy/domain/equip_slot.dart';

enum ItemRarity { common, rare, epic, legendary }

enum ItemType { cardSkin, background, profilePicture }

extension ItemTypeSlot on ItemType {
  EquipSlot get slot => switch (this) {
        ItemType.cardSkin => EquipSlot.skin,
        ItemType.background => EquipSlot.background,
        ItemType.profilePicture => EquipSlot.profilePicture,
      };
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

/// Valor do campo type em shop_items (validado pelas regras).
String catalogTypeName(ItemType type) => switch (type) {
      ItemType.cardSkin => 'skin',
      ItemType.background => 'background',
      ItemType.profilePicture => 'profilePicture',
    };

/// Valor do campo rarity em shop_items.
String catalogRarityName(ItemRarity rarity) => rarity.name;

String rarityLabel(ItemRarity rarity) => switch (rarity) {
      ItemRarity.common => 'Comum',
      ItemRarity.rare => 'Raro',
      ItemRarity.epic => 'Épico',
      ItemRarity.legendary => 'Lendário',
    };
