import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/auth_exception.dart';
import '../models/sign_up_data.dart';
import 'profile_repository.dart';

abstract interface class AuthRepository {
  /// Lanca [AuthException] (nunca FirebaseAuthException).
  Future<void> signIn({required String email, required String password});

  /// Cria a conta Auth e o perfil: ou existem ambos, ou nenhum (rollback).
  /// Lanca [AuthException]; profileCreationFailed indica rollback tentado.
  Future<void> register(SignUpData data);

  Future<void> signOut();

  // Ponto de extensao (etapa 11, NAO implementar agora):
  //   Future<void> reauthenticate(String password);
  //     (EmailAuthProvider.credential + user.reauthenticateWithCredential)
  //   Future<void> deleteAccount();   // apagar dados, depois user.delete()
  // AuthErrorCode.requiresRecentLogin ja existe para mapear o erro.
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuth auth,
    required ProfileRepository profile,
    this.profileTimeout = const Duration(seconds: 20),
  })  : _auth = auth,
        _profile = profile;

  final FirebaseAuth _auth;
  final ProfileRepository _profile;

  /// Com persistencia offline o commit nao rejeita, fica em fila; sem o
  /// timeout o cadastro ficaria preso. Estourado, so faz signOut (sem delete).
  final Duration profileTimeout;

  AuthException _map(FirebaseAuthException e) => AuthException(
        authErrorCodeFromFirebase(e.code),
        detail: e.message,
      );

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      debugPrint('signIn falhou: ${e.code}');
      throw _map(e);
    }
  }

  @override
  Future<void> register(SignUpData data) async {
    final User user;
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: data.email,
        password: data.password,
      );
      user = cred.user!;
    } on FirebaseAuthException catch (e) {
      debugPrint('register falhou: ${e.code}');
      throw _map(e);
    }
    try {
      await user.updateDisplayName(data.name);
      await _profile
          .createProfile(
            user: user,
            name: data.name,
            birthDate: data.birthDate,
            birthTime: data.birthTime,
            birthPlace: data.birthPlace,
            zodiacSign: data.zodiacSign,
          )
          .timeout(profileTimeout);
    } on TimeoutException {
      // Commit lento/ambiguo: o write pendente pode efetivar depois. Apagar o
      // usuario Auth deixaria users/{uid} e publicProfiles/{uid} orfaos (sem
      // caminho de exclusao pelo cliente). So encerra a sessao.
      debugPrint('createProfile estourou o timeout; sem rollback');
      try {
        await _auth.signOut();
      } catch (_) {}
      throw const AuthException(AuthErrorCode.profileCreationTimeout);
    } catch (e) {
      debugPrint('createProfile falhou, rollback: ${e.runtimeType}');
      var deleted = false;
      try {
        await user.delete();
        deleted = true;
      } catch (_) {}
      try {
        await _auth.signOut();
      } catch (_) {}
      throw AuthException(
        AuthErrorCode.profileCreationFailed,
        rollbackFailed: !deleted,
      );
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
