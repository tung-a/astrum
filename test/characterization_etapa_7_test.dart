// Testes de caracterizacao da etapa 7 (refatoracao pura): travam valores que
// nao podem mudar ao dividir data/ e models/ e centralizar constantes.
import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/core/astro/zodiac.dart';
import 'package:astrum/data/profile_pictures.dart';
import 'package:astrum/models/shop_item.dart';
import 'package:astrum/data/catalog_seed.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/services/economy.dart';
import 'package:astrum/services/economy_exceptions.dart';
import 'package:astrum/features/profile/data/profile_repository.dart';
import 'package:astrum/features/profile/data/public_profile_sync.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

const _slugs = {
  'Áries': 'aries',
  'Touro': 'touro',
  'Gêmeos': 'gemeos',
  'Câncer': 'cancer',
  'Leão': 'leao',
  'Virgem': 'virgem',
  'Libra': 'libra',
  'Escorpião': 'escorpiao',
  'Sagitário': 'sagitario',
  'Capricórnio': 'capricornio',
  'Aquário': 'aquario',
  'Peixes': 'peixes',
};

const _zodiacFiles = {
  'aquario': 'Aquarius',
  'aries': 'Aries',
  'cancer': 'Cancer',
  'capricornio': 'Capricorn',
  'gemeos': 'Gemini',
  'leao': 'Leo',
  'libra': 'Libra',
  'peixes': 'Pisces',
  'sagitario': 'Sagittarius',
  'escorpiao': 'Scorpio',
  'touro': 'Taurus',
  'virgem': 'Virgo',
};

void main() {
  group('seed do catalogo', () {
    test('itens base: ids, tipos, raridades e precos', () {
      final base = {
        for (final i in shopCatalog.where((i) => !i.id.startsWith('pfp_')))
          i.id: (i.type, i.rarity, i.price),
      };
      expect(base, {
        'skin_classic': (ItemType.cardSkin, ItemRarity.common, 0),
        'skin_gold': (ItemType.cardSkin, ItemRarity.legendary, 2000),
        'skin_cyber': (ItemType.cardSkin, ItemRarity.epic, 1200),
        'skin_dark': (ItemType.cardSkin, ItemRarity.rare, 800),
        'bg_void': (ItemType.background, ItemRarity.common, 0),
        'bg_nebula': (ItemType.background, ItemRarity.epic, 1500),
        'bg_temple': (ItemType.background, ItemRarity.rare, 500),
      });
    });

    test('avatares por signo e variante', () {
      const variants = {
        'common': (ItemRarity.common, 500, 'Comum'),
        'rare': (ItemRarity.rare, 800, 'Raro'),
        'epic': (ItemRarity.epic, 1200, 'Épico'),
        'legendary': (ItemRarity.legendary, 1800, 'Lendário'),
      };
      expect(profilePictureShopCatalog, hasLength(48));
      final byId = {for (final i in profilePictureShopCatalog) i.id: i};
      for (final sign in zodiacSigns) {
        for (final v in variants.entries) {
          final item = byId['pfp_${_slugs[sign]}_${v.key}']!;
          expect(item.type, ItemType.profilePicture);
          expect(item.rarity, v.value.$1);
          expect(item.price, v.value.$2);
          expect(item.name, 'Avatar $sign · ${v.value.$3}');
          expect(item.description, 'Um avatar astral inspirado em $sign.');
        }
      }
    });

    test('catalogo completo: 67 itens e avatares zodiacais gratuitos', () {
      expect(shopCatalog, hasLength(55));
      expect(fullShopCatalog, hasLength(67));
      expect(fullShopCatalog.map((i) => i.id).toSet(), hasLength(67));
      for (final sign in zodiacSigns) {
        final item = fullShopCatalog
            .singleWhere((i) => i.id == 'pfp_zodiac_${_slugs[sign]}');
        expect(item.type, ItemType.profilePicture);
        expect(item.rarity, ItemRarity.common);
        expect(item.price, 0);
        expect(item.name, 'Avatar $sign · Essência Zodiacal');
      }
    });

    test('nomes de catalogo e rotulos', () {
      expect(ItemType.values.map(catalogTypeName).toList(),
          ['skin', 'background', 'profilePicture']);
      expect(ItemRarity.values.map(catalogRarityName).toList(),
          ['common', 'rare', 'epic', 'legendary']);
      expect(ItemRarity.values.map(rarityLabel).toList(),
          ['Comum', 'Raro', 'Épico', 'Lendário']);
    });
  });

  group('profilePictureAssetPath', () {
    test('todos os ids de avatar', () {
      for (final sign in zodiacSigns) {
        final slug = _slugs[sign]!;
        expect(profilePictureAssetPath('pfp_zodiac_$slug'),
            'assets/images/zodiac/${_zodiacFiles[slug]}_pfp.png');
        expect(defaultProfilePictureId(sign), 'pfp_zodiac_$slug');
        for (final key in ['common', 'rare', 'epic', 'legendary']) {
          expect(profilePictureAssetPath('pfp_${slug}_$key'),
              'assets/images/profile-pictures/$slug/$key.png');
        }
      }
    });

    test('ids invalidos devolvem null', () {
      expect(profilePictureAssetPath('skin_classic'), isNull);
      expect(profilePictureAssetPath('pfp_zodiac_xx'), isNull);
      expect(profilePictureAssetPath('pfp_aries_mythic'), isNull);
      expect(profilePictureAssetPath('pfp_xx_common'), isNull);
      expect(profilePictureAssetPath(''), isNull);
      expect(defaultProfilePictureId(null), '');
      expect(defaultProfilePictureId(''), '');
    });
  });

  group('AppUser.fromFirebase sem documento', () {
    test('defaults', () {
      final u = AppUser.fromFirebase(
          uid: 'u', email: 'e@x.com', displayName: 'Viajante', data: null);
      expect(u.uid, 'u');
      expect(u.email, 'e@x.com');
      expect(u.name, 'Viajante');
      expect(u.role, 'user');
      expect(u.isAdmin, isFalse);
      expect(u.zodiacSign, '');
      expect(u.birthDate, '');
      expect(u.birthTime, '');
      expect(u.birthPlace, '');
      expect(u.stardust, 0);
      expect(u.inventory, ['skin_classic', 'bg_void']);
      expect(u.equippedSkin, 'skin_classic');
      expect(u.equippedBackground, 'bg_void');
      expect(u.equippedProfilePicture, isNull);
      expect(u.astralMap, isEmpty);
      expect(u.notificationsEnabled, isTrue);
      expect(u.publicProfile, isTrue);
      expect(u.showSign, isTrue);
    });

    test('construtor padrao tem os mesmos defaults', () {
      const u = AppUser(uid: 'u', email: 'e', name: 'n');
      expect(u.role, 'user');
      expect(u.inventory, ['skin_classic', 'bg_void']);
      expect(u.equippedSkin, 'skin_classic');
      expect(u.equippedBackground, 'bg_void');
      expect(u.stardust, 0);
    });
  });

  test('payload completo de createProfile', () async {
    final db = FakeFirebaseFirestore();
    final repo = ProfileRepository(
        db: db, sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth()));
    await repo.createProfile(
      user: FakeUser('nova', email: 'nova@example.com'),
      name: 'Nova',
      birthDate: '21/03/2000',
      birthTime: '10:00',
      birthPlace: 'SP',
      zodiacSign: 'Áries',
    );
    final u = (await db.collection('users').doc('nova').get()).data()!;
    expect(u, {
      'name': 'Nova',
      'email': 'nova@example.com',
      'birthDate': '21/03/2000',
      'birthTime': '10:00',
      'birthPlace': 'SP',
      'role': 'user',
      'zodiacSign': 'Áries',
      'astrologyData': {'sun': 'Áries', 'moon': null, 'ascendant': null},
      'wallet': {'stardust': 500},
      'inventory': ['skin_classic', 'bg_void', 'pfp_zodiac_aries'],
      'equipped': {
        'skin': 'skin_classic',
        'background': 'bg_void',
        'profilePicture': 'pfp_zodiac_aries',
      },
      'preferences': {
        'notifications': true,
        'publicProfile': true,
        'showSign': true,
      },
    });
    final pub =
        (await db.collection('publicProfiles').doc('nova').get()).data()!;
    expect(pub['name'], 'Nova');
    expect(pub['avatar'], 'pfp_zodiac_aries');
  });

  test('createProfile sem signo: inventario base e sem avatar', () async {
    final db = FakeFirebaseFirestore();
    final repo = ProfileRepository(
        db: db, sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth()));
    await repo.createProfile(
      user: FakeUser('n2', email: 'n2@example.com'),
      name: 'N2',
      birthDate: '',
      birthTime: '',
      birthPlace: '',
      zodiacSign: '',
    );
    final u = (await db.collection('users').doc('n2').get()).data()!;
    expect(u['inventory'], ['skin_classic', 'bg_void']);
    expect((u['equipped'] as Map)['profilePicture'], isNull);
  });

  group('economia: textos e valores', () {
    test('check-in credita 25', () {
      expect(
          computeCheckIn(stardust: 10, lastCheckIn: null, today: '2026-01-02'),
          35);
      expect(checkInReward, 25);
    });

    test('mensagens das excecoes', () {
      expect(const AlreadyOwnedException().toString(),
          'Você já possui este item.');
      expect(const InsufficientFundsException().toString(),
          'Poeira Estelar insuficiente.');
      expect(const NotPurchasableException().toString(),
          'Este item não está disponível para compra.');
      expect(const CatalogUnavailableException().toString(),
          'Catálogo indisponível.');
      expect(const AlreadyCheckedInException().toString(),
          'Você já fez o check-in de hoje.');
    });
  });
}
