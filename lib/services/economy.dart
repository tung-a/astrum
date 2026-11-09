/// Logica pura de economia (compra e check-in). Sem Firebase, para ser testada
/// e reutilizada dentro de transacoes. O preco vem do catalogo. Precisa permanecer coerente com
/// `isPurchase()` e `isCheckin()` em firestore.rules.
library;

const int checkInReward = 25;

/// Erros de economia (cada um vira uma mensagem na tela).
sealed class EconomyException implements Exception {
  const EconomyException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AlreadyOwnedException extends EconomyException {
  const AlreadyOwnedException() : super('Você já possui este item.');
}

class InsufficientFundsException extends EconomyException {
  const InsufficientFundsException()
      : super('Poeira Estelar insuficiente.');
}

/// Item sem entrada ativa no catalogo (shop_items) ou com preco invalido: as
/// regras do Firestore recusariam a gravacao.
class NotPurchasableException extends EconomyException {
  const NotPurchasableException()
      : super('Este item não está disponível para compra.');
}

/// Catalogo vazio (shop_items nao publicado ou ainda nao carregado): nao ha
/// preco confiavel, entao nao se compra com preco local.
class CatalogUnavailableException extends EconomyException {
  const CatalogUnavailableException() : super('Catálogo indisponível.');
}

/// Entrada do catalogo `shop_items/{itemId}` (preco validado pelas regras).
class CatalogEntry {
  const CatalogEntry({
    required this.price,
    required this.type,
    required this.rarity,
    required this.active,
  });

  final int price;
  final String type;
  final String rarity;
  final bool active;

  factory CatalogEntry.fromMap(Map<String, dynamic> data) => CatalogEntry(
        price: (data['price'] as num?)?.toInt() ?? -1,
        type: data['type'] as String? ?? '',
        rarity: data['rarity'] as String? ?? '',
        active: data['active'] == true,
      );
}

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

class AlreadyCheckedInException extends EconomyException {
  const AlreadyCheckedInException()
      : super('Você já fez o check-in de hoje.');
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
