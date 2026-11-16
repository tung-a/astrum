/// A intencao nao pode ser entregue: a conta do destinatario nao existe mais
/// (as regras negam a criacao em caixa de conta sem perfil).
class RecipientUnavailableException implements Exception {
  const RecipientUnavailableException();
  @override
  String toString() => 'RecipientUnavailableException';
}
