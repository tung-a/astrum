import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/features/economy/data/catalog_repository.dart';
import 'package:astrum/features/economy/data/economy_repository.dart';
import 'package:astrum/features/economy/domain/catalog_entry.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
