import '../core/firebase/rules_contract.dart';

/// Tamanhos maximos aceitos por `profileShapeOk` em firestore.rules
/// (manter em sincronia com as regras).
class SignUpLimits {
  static const name = profileNameMax;
  static const email = profileEmailMax;
  static const birthDate = profileBirthDateMax;
  static const birthTime = profileBirthTimeMax;
  static const birthPlace = profileBirthPlaceMax;
}

/// Mensagem de erro se algum campo estoura o limite das regras; null se ok.
/// Funcao pura (testavel sem widget). Valores em branco sao aceitos aqui.
String? signUpLengthError({
  String name = '',
  String email = '',
  String birthDate = '',
  String birthTime = '',
  String birthPlace = '',
}) {
  if (name.trim().length > SignUpLimits.name) {
    return 'O nome deve ter no máximo ${SignUpLimits.name} caracteres.';
  }
  if (email.trim().length > SignUpLimits.email) {
    return 'O email deve ter no máximo ${SignUpLimits.email} caracteres.';
  }
  if (birthDate.length > SignUpLimits.birthDate) {
    return 'Data de nascimento inválida.';
  }
  if (birthTime.length > SignUpLimits.birthTime) {
    return 'Hora de nascimento inválida.';
  }
  if (birthPlace.length > SignUpLimits.birthPlace) {
    return 'A cidade deve ter no máximo ${SignUpLimits.birthPlace} caracteres.';
  }
  return null;
}

/// Dados do cadastro. Nunca logar: a senha e sensivel.
class SignUpData {
  const SignUpData({
    required this.name,
    required this.email,
    required this.password,
    required this.birthDate,
    required this.birthTime,
    required this.birthPlace,
    required this.zodiacSign,
  });

  final String name;
  final String email;
  final String password;
  final String birthDate;
  final String birthTime;
  final String birthPlace;
  final String zodiacSign;

  @override
  String toString() => 'SignUpData(email: $email, password: ***)';
}
