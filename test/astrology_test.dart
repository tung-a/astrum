import 'dart:io';

import 'package:astrum/data/astrology.dart';
import 'package:astrum/data/cosmetics.dart';
import 'package:astrum/data/moon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calcula signo solar', () {
    expect(sunSignFromDate(21, 3), 'Áries');
    expect(sunSignFromDate(15, 1), 'Capricórnio');
    expect(sunSignFromDate(1, 5), 'Touro');
  });

  test('sinergia do mesmo elemento é máxima', () {
    final result = getAstralSynergy('Áries', 'Leão');
    expect(result.score, 5);
    expect(result.title, 'Espelhos da Alma');
  });

  test('lua tem fase nomeada', () {
    final moon = moonFor(DateTime.utc(2026, 10, 15));
    expect(moon.phaseName, isNotEmpty);
    expect(moon.emoji, isNotEmpty);
  });

  test('cada signo tem avatar zodiacal e variantes disponíveis', () {
    for (final sign in zodiacSigns) {
      final defaultAvatar =
          profilePictureAssetPath(defaultProfilePictureId(sign));
      expect(defaultAvatar, isNotNull);
      expect(File(defaultAvatar!).existsSync(), isTrue,
          reason: 'Avatar de $sign');

      for (final item in profilePictureShopCatalog
          .where((item) => item.name.contains(sign))) {
        final asset = profilePictureAssetPath(item.id);
        expect(asset, isNotNull);
        expect(File(asset!).existsSync(), isTrue, reason: item.id);
      }
    }
  });
}
