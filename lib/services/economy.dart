/// Logica pura de economia (compra e check-in). Sem Firebase, para ser testada
/// e reutilizada dentro de transacoes. O preco vem do catalogo. Precisa permanecer coerente com
/// `isPurchase()` e `isCheckin()` em firestore.rules.
library;

import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/models/catalog_entry.dart';
import 'package:astrum/services/economy_exceptions.dart';

/// Preco de [itemId] segundo o [catalog]. Lanca [CatalogUnavailableException]
/// se o catalogo estiver vazio e [NotPurchasableException] se o item nao existe,
/// esta inativo ou tem preco invalido.
int resolvePrice(Map<String, CatalogEntry> catalog, String itemId) {
  if (catalog.isEmpty) throw const CatalogUnavailableException();
  final entry = catalog[itemId];
  if (entry == null || !entry.active || entry.price < 0) {
    throw const NotPurchasableException();
  }
  return entry.price;
}

class PurchaseResult {
  const PurchaseResult({required this.stardust, required this.inventory});
  final int stardust;
  final List<String> inventory;
}

/// Decide a compra a partir do estado lido dentro da transacao.
/// Lanca [EconomyException] sem efeito colateral se nao for possivel.
PurchaseResult computePurchase({
  required int stardust,
  required List<String> inventory,
  required String itemId,
  required int price,
}) {
  if (inventory.contains(itemId)) throw const AlreadyOwnedException();
  // Preco 0: item gratuito do catalogo, saldo inalterado (as regras exigem
  // saldo novo == saldo antigo - preco).
  if (price < 0) throw const NotPurchasableException();
  if (stardust < price) throw const InsufficientFundsException();
  return PurchaseResult(
    stardust: stardust - price,
    inventory: [...inventory, itemId],
  );
}

/// Decide o check-in. [today] e `yyyy-MM-dd`. Retorna o novo saldo.
/// Datas sao comparaveis como string; se o ultimo check-in for >= hoje, nao
/// credita (as regras exigem data estritamente crescente).
int computeCheckIn({
  required int stardust,
  required String? lastCheckIn,
  required String today,
}) {
  if (lastCheckIn != null && lastCheckIn.compareTo(today) >= 0) {
    throw const AlreadyCheckedInException();
  }
  return stardust + checkInReward;
}
