import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/core/firebase/firebase_providers.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// uid do usuario logado. Os providers de streams por usuario dependem so
/// disto (via `select`), para nao reabrir listeners quando saldo, horoscopo
/// ou itens equipados mudam em `users/{uid}`.
final currentUidProvider = Provider<String?>((ref) {
  // Vem da auth, nao do perfil: durante o loading do perfil de outro usuario o
  // valueOrNull do perfil ainda retem o anterior. AsyncError tambem retem o
  // valor anterior, entao hasError e testado primeiro (erro conta como null).
  return ref.watch(authStateProvider.select(
    (a) => a.hasError ? null : a.valueOrNull?.uid,
  ));
});
