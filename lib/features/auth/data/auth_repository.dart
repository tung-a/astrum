import 'dart:async';

import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/auth/domain/sign_up_data.dart';
import 'package:astrum/features/profile/data/profile_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

abstract interface class AuthRepository {
  /// Lanca [AuthException] (nunca FirebaseAuthException).
  Future<void> signIn({required String email, required String password});

  /// Cria a conta Auth e o perfil: ou existem ambos, ou nenhum (rollback).
  /// Lanca [AuthException]; profileCreationFailed indica rollback tentado.
  Future<void> register(SignUpData data);

  Future<void> signOut();

  /// Reautentica o usuario logado com a senha (exigido antes de excluir a
  /// conta). Lanca [AuthException]; nunca registra a senha.
  ///
  /// Hoje o unico provedor e e-mail e senha. Se entrar Google ou Apple, a
  /// reautenticacao muda (credencial do provedor) e, no Sign in with Apple, a
  /// exclusao precisa revogar o token (`revokeTokenWithAuthorizationCode`).
  Future<void> reauthenticate(String password);

  /// Exclui o usuario Auth (`user.delete()`); deve ser o ULTIMO passo da
  /// exclusao de conta (depois dele nenhuma chamada ao Firestore tem
  /// `request.auth`). `requires-recent-login` vira [AuthException] com
  /// [AuthErrorCode.requiresRecentLogin]; usuario ja excluido (outro
  /// aparelho) conta como sucesso.
  Future<void> deleteAccount();
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

  @override
  Future<void> reauthenticate(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null ||
        email == null ||
        !user.providerData.any((p) => p.providerId == 'password')) {
      throw const AuthException(AuthErrorCode.unknown);
    }
    try {
      await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: password));
    } on FirebaseAuthException catch (e) {
      debugPrint('reauthenticate falhou: ${e.code}');
      throw AuthException(authErrorCodeFromFirebase(e.code));
    }
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return; // ja excluida/encerrada em outro lugar
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      debugPrint('deleteAccount falhou: ${e.code}');
      if (e.code == 'user-not-found' ||
          e.code == 'user-token-expired' ||
          e.code == 'no-current-user') {
        // Outro aparelho ja excluiu a conta: so encerra a sessao local.
        try {
          await _auth.signOut();
        } catch (_) {}
        return;
      }
      throw AuthException(authErrorCodeFromFirebase(e.code));
    }
  }
}
