import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:astrum/features/economy/domain/catalog_entry.dart';

/// Leitura do catalogo da loja (shop_items).
class CatalogRepository {
  CatalogRepository(this._db);

  final FirebaseFirestore _db;

  Stream<Map<String, CatalogEntry>> watchShopCatalog() {
    return _db.collection('shop_items').snapshots().map((snap) => {
          for (final d in snap.docs) d.id: CatalogEntry.fromMap(d.data()),
        });
  }
}
