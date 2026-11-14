import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/firebase/rules_contract.dart';

/// SHA-256 (hex minusculo, 64 caracteres) do e-mail em minusculas e sem
/// espacos nas pontas. E o unico identificador de busca de amigo exposto em
/// `publicProfiles/{uid}`; o e-mail em si nunca sai de `users/{uid}`.
String hashEmail(String email) =>
    sha256.convert(utf8.encode(email.trim().toLowerCase())).toString();

/// Documento `publicProfiles/{uid}`: so nome, avatar e hash do e-mail
/// (as regras do Firestore recusam qualquer outro campo).
/// Devolve null quando nao ha e-mail ou nome para publicar.
Map<String, dynamic>? buildPublicProfile({
  required String name,
  required String? avatar,
  required String email,
}) {
  final cleanName = name.trim();
  if (email.trim().isEmpty || cleanName.isEmpty) return null;
  return {
    'name': cleanName.length > publicNameMax
        ? cleanName.substring(0, publicNameMax)
        : cleanName,
    'avatar': avatar ?? '',
    'emailHash': hashEmail(email),
  };
}
