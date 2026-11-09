/// Logica pura de economia (compra e check-in). Sem Firebase, para ser testada
/// e reutilizada dentro de transacoes. Precisa permanecer coerente com
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

/// Item com preco <= 0 nao pode ser "comprado": as regras exigem que o saldo
/// diminua em toda compra.
class NotPurchasableException extends EconomyException {
  const NotPurchasableException()
      : super('Este item não está disponível para compra.');
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
  if (price <= 0) throw const NotPurchasableException();
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
