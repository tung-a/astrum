import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_paths.dart';
import '../models/equip_slot.dart';
import '../models/catalog_entry.dart';
import 'economy.dart';
import 'economy_exceptions.dart';
import 'equip_slot_field.dart';
import 'public_profile_sync.dart';

/// Todo credito e debito de `wallet.stardust` passa por aqui; nenhum outro
/// repositorio pode gravar `wallet.*`.
abstract interface class EconomyRepository {
  /// Compra atomica; se [equipSlot] vier, equipa na mesma gravacao.
  /// Lanca [EconomyException] sem gravar quando invalida.
  Future<void> purchaseItem({
    required String uid,
    required String itemId,
    EquipSlot? equipSlot,
  });

  /// Check-in diario; [today] = yyyy-MM-dd. Lanca [AlreadyCheckedInException].
  Future<void> dailyCheckIn({required String uid, required String today});
}

class FirestoreEconomyRepository implements EconomyRepository {
  FirestoreEconomyRepository({
    required FirebaseFirestore db,
    required PublicProfileSync sync,
  })  : _db = db,
        _sync = sync;

  final FirebaseFirestore _db;
  final PublicProfileSync _sync;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.userDoc(uid);

  /// Compra atomica: le o perfil e o preco do catalogo (shop_items) dentro da
  /// transacao, valida e grava saldo e inventario completo (a regra exige o
  /// inventario antigo + 1 item, e o item novo no fim da lista).
  /// Se [equipSlot] for informado, equipa o item na mesma gravacao.
  /// Lanca [EconomyException] sem gravar nada quando a compra nao e valida.
  @override
  Future<void> purchaseItem({
    required String uid,
    required String itemId,
    EquipSlot? equipSlot,
  }) {
    final ref = _userDoc(uid);
    final itemRef = _db.shopItemDoc(itemId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final itemSnap = await tx.get(itemRef);
      final data = snap.data();
      if (data == null) throw StateError('Perfil não encontrado.');
      final itemData = itemSnap.data();
      if (itemData == null) throw const NotPurchasableException();
      final price =
          resolvePrice({itemId: CatalogEntry.fromMap(itemData)}, itemId);
      final result = computePurchase(
        stardust: ((data['wallet'] as Map?)?['stardust'] as num?)?.toInt() ?? 0,
        inventory: ((data['inventory'] as List?) ?? const []).cast<String>(),
        itemId: itemId,
        price: price,
      );
      tx.update(ref, {
        'wallet.stardust': result.stardust,
        'inventory': result.inventory,
        if (equipSlot != null) equipSlot.fieldPath: itemId,
      });
    }).then((_) async {
      if (equipSlot?.touchesPublicProfile ?? false) {
        await _sync.syncFromUser(uid);
      }
    });
  }

  /// Check-in diario atomico. [today] no formato `yyyy-MM-dd` (data local; as
  /// regras aceitam UTC +-1 dia). Lanca [AlreadyCheckedInException] se ja feito.
  @override
  Future<void> dailyCheckIn({required String uid, required String today}) {
    final ref = _userDoc(uid);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) throw StateError('Perfil não encontrado.');
      final newStardust = computeCheckIn(
        stardust: ((data['wallet'] as Map?)?['stardust'] as num?)?.toInt() ?? 0,
        lastCheckIn: data['dailyCheckIn'] as String?,
        today: today,
      );
      tx.update(ref, {
        'wallet.stardust': newStardust,
        'dailyCheckIn': today,
      });
    });
  }
}
