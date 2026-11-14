import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/theme/cosmetics_style.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/services/catalog_repository.dart';
import 'package:astrum/models/catalog_entry.dart';
import 'package:astrum/services/economy_repository.dart';

final catalogRepositoryProvider =
    Provider((ref) => CatalogRepository(ref.watch(firestoreProvider)));

final economyRepositoryProvider = Provider<EconomyRepository>(
  (ref) => FirestoreEconomyRepository(
    db: ref.watch(firestoreProvider),
    sync: ref.watch(publicProfileSyncProvider),
  ),
);

/// Catalogo da loja (shop_items): fonte unica de preco e disponibilidade.
final shopCatalogProvider = StreamProvider<Map<String, CatalogEntry>>((ref) {
  return ref.watch(catalogRepositoryProvider).watchShopCatalog();
});

final equippedSkinProvider = Provider<SkinStyle>((ref) {
  final id =
      ref.watch(profileProvider).valueOrNull?.equippedSkin ?? defaultSkinId;
  return cosmeticStyles[id] ?? cosmeticStyles[defaultSkinId]!;
});

final equippedBackgroundProvider = Provider<List<Color>>((ref) {
  final id = ref.watch(profileProvider).valueOrNull?.equippedBackground ??
      defaultBackgroundId;
  return cosmeticBackgrounds[id] ?? cosmeticBackgrounds[defaultBackgroundId]!;
});

