import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/auth/domain/sign_up_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('signUpLengthError', () {
    test('aceita valores nos limites das regras', () {
      expect(
          signUpLengthError(
            name: 'a' * 100,
            email: 'e' * 254,
            birthDate: '01/01/2000',
            birthTime: '12:30',
            birthPlace: 'c' * 200,
          ),
          isNull);
    });

    test('rejeita acima dos limites', () {
      expect(signUpLengthError(name: 'a' * 101), contains('nome'));
      expect(signUpLengthError(email: 'e' * 255), contains('email'));
      expect(signUpLengthError(birthDate: 'd' * 21), isNotNull);
      expect(signUpLengthError(birthTime: 't' * 11), isNotNull);
      expect(signUpLengthError(birthPlace: 'c' * 201), contains('cidade'));
    });
  });

  test('mapeia codigos do Firebase', () {
    expect(authErrorCodeFromFirebase('invalid-credential'),
        AuthErrorCode.invalidCredentials);
    expect(authErrorCodeFromFirebase('email-already-in-use'),
        AuthErrorCode.emailInUse);
    expect(
        authErrorCodeFromFirebase('weak-password'), AuthErrorCode.weakPassword);
    expect(
        authErrorCodeFromFirebase('invalid-email'), AuthErrorCode.invalidEmail);
    expect(
        authErrorCodeFromFirebase('user-disabled'), AuthErrorCode.userDisabled);
    expect(authErrorCodeFromFirebase('too-many-requests'),
        AuthErrorCode.tooManyRequests);
    expect(authErrorCodeFromFirebase('network-request-failed'),
        AuthErrorCode.network);
    expect(authErrorCodeFromFirebase('wrong-password'),
        AuthErrorCode.invalidCredentials);
    expect(authErrorCodeFromFirebase('requires-recent-login'),
        AuthErrorCode.requiresRecentLogin);
    expect(authErrorCodeFromFirebase('outro'), AuthErrorCode.unknown);
  });

  test('textos do login identicos aos atuais', () {
    expect(
        loginErrorMessage(
            const AuthException(AuthErrorCode.invalidCredentials)),
        'Email ou senha inválidos.');
    expect(loginErrorMessage(const AuthException(AuthErrorCode.network)),
        'Não foi possível entrar.');
    expect(loginErrorMessage(const AuthException(AuthErrorCode.unknown)),
        'Não foi possível entrar.');
  });

  test('textos do cadastro', () {
    expect(
        signUpErrorMessage(
            const AuthException(AuthErrorCode.emailInUse, detail: 'msg fb')),
        'Este e-mail já tem uma conta. Entre com seu e-mail e senha.');
    expect(signUpErrorMessage(const AuthException(AuthErrorCode.unknown)),
        'Não foi possível criar a conta');
    expect(
        signUpErrorMessage(
            const AuthException(AuthErrorCode.profileCreationFailed)),
        'Não foi possível concluir o cadastro. Tente novamente.');
    expect(
        signUpErrorMessage(const AuthException(
            AuthErrorCode.profileCreationFailed,
            rollbackFailed: true)),
        contains('Se persistir, entre em contato.'));
  });

  test('SignUpData.toString e AuthException nao expoem a senha', () {
    const d = SignUpData(
        name: 'A',
        email: 'a@b.c',
        password: 'segredo123',
        birthDate: '',
        birthTime: '',
        birthPlace: '',
        zodiacSign: 'Aries');
    expect(d.toString(), isNot(contains('segredo123')));
    expect(const AuthException(AuthErrorCode.unknown).toString(),
        isNot(contains('segredo123')));
  });

  test('deleteAccountErrorMessage: textos da exclusao', () {
    String m(AuthErrorCode c, {bool after = false}) =>
        deleteAccountErrorMessage(AuthException(c), afterDataDeleted: after);
    expect(m(AuthErrorCode.invalidCredentials),
        'Senha incorreta. Nada foi apagado.');
    expect(m(AuthErrorCode.invalidCredentials, after: true),
        'Senha incorreta. Tente de novo.');
    expect(m(AuthErrorCode.tooManyRequests),
        'Muitas tentativas. Aguarde alguns minutos e tente de novo.');
    expect(m(AuthErrorCode.network),
        contains('O que já foi apagado continua apagado.'));
    expect(m(AuthErrorCode.requiresRecentLogin),
        'Por segurança, digite sua senha novamente para concluir.');
    expect(m(AuthErrorCode.unknown), contains('Toque em Tentar de novo.'));
  });

  test('deleteAccountErrorMessage: antes da cascata nao diz que apagou', () {
    String m(AuthErrorCode c) =>
        deleteAccountErrorMessage(AuthException(c), partial: false);
    expect(
        m(AuthErrorCode.unknown), 'Não foi possível concluir. Tente de novo.');
    expect(m(AuthErrorCode.network), isNot(contains('já foi apagado')));
  });

  test('passwordResetErrorMessage: textos do esqueci minha senha', () {
    String m(AuthErrorCode c) => passwordResetErrorMessage(AuthException(c));
    expect(m(AuthErrorCode.invalidEmail), 'E-mail inválido.');
    expect(
        m(AuthErrorCode.network), 'Sem conexão. Conecte-se e tente de novo.');
    expect(m(AuthErrorCode.tooManyRequests),
        'Muitas tentativas. Aguarde alguns minutos e tente de novo.');
    expect(m(AuthErrorCode.unknown),
        'Não foi possível enviar o link. Tente de novo.');
  });
}
