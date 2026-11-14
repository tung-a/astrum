/// Falhas de autenticacao expostas a UI (a UI nao importa Firebase).
enum AuthErrorCode {
  invalidCredentials,
  emailInUse,
  weakPassword,
  invalidEmail,
  userDisabled,
  tooManyRequests,
  network,

  /// Ponto de extensao da etapa 11 (reautenticacao antes de excluir conta).
  requiresRecentLogin,

  /// Auth criado, perfil falhou, rollback executado.
  profileCreationFailed,

  /// Commit do perfil sem resposta no prazo: a conta Auth foi mantida (o write
  /// pode efetivar depois); so signOut.
  profileCreationTimeout,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.code, {this.detail, this.rollbackFailed = false});

  final AuthErrorCode code;

  /// Mensagem original do Firebase (exibida no cadastro); nunca contem senha.
  final String? detail;

  /// So em [AuthErrorCode.profileCreationFailed]: o delete do usuario Auth
  /// tambem falhou (conta Auth orfa).
  final bool rollbackFailed;

  @override
  String toString() => 'AuthException($code, rollbackFailed: $rollbackFailed)';
}

/// Mapeia o codigo do FirebaseAuthException para [AuthErrorCode].
AuthErrorCode authErrorCodeFromFirebase(String code) => switch (code) {
      'invalid-credential' => AuthErrorCode.invalidCredentials,
      'email-already-in-use' => AuthErrorCode.emailInUse,
      'weak-password' => AuthErrorCode.weakPassword,
      'invalid-email' => AuthErrorCode.invalidEmail,
      'user-disabled' => AuthErrorCode.userDisabled,
      'too-many-requests' => AuthErrorCode.tooManyRequests,
      'network-request-failed' => AuthErrorCode.network,
      'requires-recent-login' => AuthErrorCode.requiresRecentLogin,
      _ => AuthErrorCode.unknown,
    };

/// Texto de erro do login (identico ao anterior).
String loginErrorMessage(AuthException e) =>
    e.code == AuthErrorCode.invalidCredentials
        ? 'Email ou senha inválidos.'
        : 'Não foi possível entrar.';

/// Texto de erro do cadastro.
String signUpErrorMessage(AuthException e) {
  if (e.code == AuthErrorCode.profileCreationTimeout) {
    return 'O cadastro está demorando mais que o esperado; verifique a '
        'conexão e entre com seu e-mail e senha em instantes.';
  }
  if (e.code == AuthErrorCode.profileCreationFailed) {
    return e.rollbackFailed
        ? 'Não foi possível concluir o cadastro. Tente novamente. '
            'Se persistir, entre em contato.'
        : 'Não foi possível concluir o cadastro. Tente novamente.';
  }
  if (e.code == AuthErrorCode.emailInUse) {
    return 'Este e-mail já tem uma conta. Entre com seu e-mail e senha.';
  }
  return e.detail ?? 'Não foi possível criar a conta';
}
