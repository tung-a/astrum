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
  const InsufficientFundsException() : super('Poeira Estelar insuficiente.');
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

class AlreadyCheckedInException extends EconomyException {
  const AlreadyCheckedInException() : super('Você já fez o check-in de hoje.');
}
