import 'package:flutter/material.dart';

import '../core/firebase/rules_contract.dart';
import '../models/shop_item.dart';

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

const cosmeticStyles = <String, SkinStyle>{
  defaultSkinId: SkinStyle(
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

const cosmeticBackgrounds = <String, List<Color>>{
  defaultBackgroundId: [Color(0xFF090612), Color(0xFF120B25)],
  'bg_nebula': [Color(0xFF2E004E), Color(0xFF000000)],
  'bg_temple': [Color(0xFF3E2723), Color(0xFF1B0000)],
};

Color rarityColor(ItemRarity rarity) => switch (rarity) {
      ItemRarity.common => const Color(0xFF90A4AE),
      ItemRarity.rare => const Color(0xFF42A5F5),
      ItemRarity.epic => const Color(0xFFAB47BC),
      ItemRarity.legendary => const Color(0xFFFFD54F),
    };
