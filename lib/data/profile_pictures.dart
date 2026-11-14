import '../core/astro/zodiac.dart';
import '../core/firebase/rules_contract.dart';
import '../models/shop_item.dart';

const profilePictureVariants = [
  (key: 'common', label: 'Comum', rarity: ItemRarity.common, price: 500),
  (key: 'rare', label: 'Raro', rarity: ItemRarity.rare, price: 800),
  (key: 'epic', label: 'Épico', rarity: ItemRarity.epic, price: 1200),
  (
    key: 'legendary',
    label: 'Lendário',
    rarity: ItemRarity.legendary,
    price: 1800
  ),
];

String defaultProfilePictureId(String? zodiacSign) {
  if (zodiacSign == null || zodiacSign.isEmpty) return '';
  final slug = zodiacSlug(zodiacSign);
  return '$zodiacAvatarPrefix$slug';
}

const _zodiacPictureFiles = {
  'Aquário': 'Aquarius_pfp.png',
  'Áries': 'Aries_pfp.png',
  'Câncer': 'Cancer_pfp.png',
  'Capricórnio': 'Capricorn_pfp.png',
  'Gêmeos': 'Gemini_pfp.png',
  'Leão': 'Leo_pfp.png',
  'Libra': 'Libra_pfp.png',
  'Peixes': 'Pisces_pfp.png',
  'Sagitário': 'Sagittarius_pfp.png',
  'Escorpião': 'Scorpio_pfp.png',
  'Touro': 'Taurus_pfp.png',
  'Virgem': 'Virgo_pfp.png',
};

String? profilePictureAssetPath(String id) {
  if (id.startsWith(zodiacAvatarPrefix)) {
    final slug = id.substring(zodiacAvatarPrefix.length);
    for (final entry in _zodiacPictureFiles.entries) {
      if (zodiacSlug(entry.key) == slug) {
        return 'assets/images/zodiac/${entry.value}';
      }
    }
    return null;
  }

  if (id.startsWith('pfp_')) {
    final parts = id.split('_');
    if (parts.length == 3 &&
        profilePictureVariants.any((variant) => variant.key == parts[2]) &&
        zodiacSigns.any((sign) => zodiacSlug(sign) == parts[1])) {
      return 'assets/images/profile-pictures/${parts[1]}/${parts[2]}.png';
    }
  }
  return null;
}
