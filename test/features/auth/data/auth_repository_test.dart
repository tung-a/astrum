import 'dart:async';

import 'package:astrum/features/auth/data/auth_repository.dart';
import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/auth/domain/sign_up_data.dart';
import 'package:astrum/features/profile/data/profile_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_firebase.dart';

/// Perfil que registra a ordem e e configuravel (sucesso, falha, nunca completa).
class _StubProfile implements ProfileRepository {
  _StubProfile(this.log);
  final List<String> log;
  Object? error;
  bool never = false;
  int createCalls = 0;

  @override
  Future<void> createProfile({
    required User user,
    required String name,
    required String birthDate,
    required String birthTime,
    required String birthPlace,
    required String zodiacSign,
  }) {
    createCalls++;
    log.add('createProfile');
    if (never) return Completer<void>().future;
    if (error != null) return Future.error(error!);
    return Future.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const _data = SignUpData(
  name: 'Nova',
  email: 'nova@x.com',
  password: 'segredo123',
  birthDate: '01/01/2000',
  birthTime: '',
  birthPlace: '',
  zodiacSign: 'Aries',
);

void main() {
  late FakeFirebaseAuth auth;
  late _StubProfile profile;
  late FirebaseAuthRepository repo;

  setUp(() {
    auth = FakeFirebaseAuth();
    profile = _StubProfile(auth.calls);
    repo = FirebaseAuthRepository(
      auth: auth,
      profile: profile,
      profileTimeout: const Duration(milliseconds: 50),
    );
  });

  group('signIn', () {
    test('sucesso', () async {
      await repo.signIn(email: 'a@b.c', password: 'x');
      expect(auth.calls, ['signIn']);
    });

    test('invalid-credential vira invalidCredentials', () async {
      auth.signInError = FirebaseAuthException(code: 'invalid-credential');
      await expectLater(
          repo.signIn(email: 'a@b.c', password: 'x'),
          throwsA(isA<AuthException>().having(
              (e) => e.code, 'code', AuthErrorCode.invalidCredentials)));
    });

    test('outros codigos mapeados ou unknown, nunca FirebaseAuthException',
        () async {
      for (final (code, expected) in [
        ('too-many-requests', AuthErrorCode.tooManyRequests),
        ('network-request-failed', AuthErrorCode.network),
        ('algo-novo', AuthErrorCode.unknown),
      ]) {
        auth.signInError = FirebaseAuthException(code: code);
        await expectLater(
            repo.signIn(email: 'a@b.c', password: 'x'),
            throwsA(
                isA<AuthException>().having((e) => e.code, 'code', expected)));
      }
    });
  });

  group('register', () {
    test(
        'sucesso: ordem createUser, updateDisplayName, createProfile; sem delete',
        () async {
      await repo.register(_data);
      expect(auth.calls, ['createUser', 'updateDisplayName', 'createProfile']);
      expect(auth.lastCreatedUser!.deleteCalls, 0);
      expect(auth.signOutCalls, 0);
    });

    test('createProfile falha: delete uma vez, signOut, rollbackFailed false',
        () async {
      profile.error = StateError('permission-denied');
      await expectLater(
          repo.register(_data),
          throwsA(isA<AuthException>()
              .having(
                  (e) => e.code, 'code', AuthErrorCode.profileCreationFailed)
              .having((e) => e.rollbackFailed, 'rollbackFailed', false)));
      expect(auth.lastCreatedUser!.deleteCalls, 1);
      expect(auth.signOutCalls, 1);
    });

    test('updateDisplayName falha: mesmo rollback, sem createProfile',
        () async {
      auth.nextUserUpdateNameError = FirebaseAuthException(code: 'x');
      await expectLater(
          repo.register(_data),
          throwsA(isA<AuthException>().having(
              (e) => e.code, 'code', AuthErrorCode.profileCreationFailed)));
      expect(profile.createCalls, 0);
      expect(auth.lastCreatedUser!.deleteCalls, 1);
      expect(auth.signOutCalls, 1);
    });

    test('delete tambem falha: signOut chamado e rollbackFailed true',
        () async {
      profile.error = StateError('falha');
      auth.nextUserDeleteError = FirebaseAuthException(code: 'network');
      await expectLater(
          repo.register(_data),
          throwsA(isA<AuthException>()
              .having(
                  (e) => e.code, 'code', AuthErrorCode.profileCreationFailed)
              .having((e) => e.rollbackFailed, 'rollbackFailed', true)));
      expect(auth.signOutCalls, 1);
    });

    test(
        'createProfile nunca completa: timeout NAO apaga o usuario, so signOut',
        () async {
      profile.never = true;
      await expectLater(
          repo.register(_data),
          throwsA(isA<AuthException>().having(
              (e) => e.code, 'code', AuthErrorCode.profileCreationTimeout)));
      expect(auth.lastCreatedUser!.deleteCalls, 0);
      expect(auth.signOutCalls, 1);
    });

    test('mensagem do timeout orienta a entrar em instantes', () {
      expect(
          signUpErrorMessage(
              const AuthException(AuthErrorCode.profileCreationTimeout)),
          allOf(contains('demorando'), contains('entre com seu e-mail')));
    });

    test('FirebaseException definitiva (permission-denied): delete e signOut',
        () async {
      profile.error = FirebaseException(
          plugin: 'cloud_firestore', code: 'permission-denied');
      await expectLater(
          repo.register(_data),
          throwsA(isA<AuthException>().having(
              (e) => e.code, 'code', AuthErrorCode.profileCreationFailed)));
      expect(auth.lastCreatedUser!.deleteCalls, 1);
      expect(auth.signOutCalls, 1);
    });

    test('falha no createUser: sem delete nem createProfile; detail preservado',
        () async {
      for (final (code, expected) in [
        ('email-already-in-use', AuthErrorCode.emailInUse),
        ('weak-password', AuthErrorCode.weakPassword),
      ]) {
        auth.createUserError =
            FirebaseAuthException(code: code, message: 'msg do firebase');
        await expectLater(
            repo.register(_data),
            throwsA(isA<AuthException>()
                .having((e) => e.code, 'code', expected)
                .having((e) => e.detail, 'detail', 'msg do firebase')));
      }
      expect(profile.createCalls, 0);
      expect(auth.lastCreatedUser, isNull);
      expect(auth.signOutCalls, 0);
    });

    test('a senha nao aparece na excecao', () async {
      profile.error = StateError('falha');
      try {
        await repo.register(_data);
        fail('deveria lancar');
      } on AuthException catch (e) {
        expect(e.toString(), isNot(contains('segredo123')));
        expect(e.detail ?? '', isNot(contains('segredo123')));
      }
    });
  });

  test('signOut delega ao FirebaseAuth', () async {
    await repo.signOut();
    expect(auth.signOutCalls, 1);
  });

  group('reauthenticate e deleteAccount', () {
    FakeUser logged({String? email = 'a@b.c'}) {
      final u = FakeUser('u1', email: email, calls: auth.calls);
      auth.setUser(u);
      return u;
    }

    test('reauthenticate usa credencial de e-mail e senha do usuario atual',
        () async {
      final u = logged();
      await repo.reauthenticate('minhasenha');
      expect(u.reauthCalls, 1);
      final cred = u.lastCredential! as EmailAuthCredential;
      expect(cred.email, 'a@b.c');
      expect(cred.password, 'minhasenha');
    });

    test('reauthenticate: senha errada vira invalidCredentials', () async {
      logged().reauthError = FirebaseAuthException(code: 'wrong-password');
      await expectLater(
          repo.reauthenticate('x'),
          throwsA(isA<AuthException>().having(
              (e) => e.code, 'code', AuthErrorCode.invalidCredentials)));
    });

    test('reauthenticate: muitas tentativas e rede', () async {
      final u = logged()
        ..reauthError = FirebaseAuthException(code: 'too-many-requests');
      await expectLater(
          repo.reauthenticate('x'),
          throwsA(isA<AuthException>()
              .having((e) => e.code, 'code', AuthErrorCode.tooManyRequests)));
      u.reauthError = FirebaseAuthException(code: 'network-request-failed');
      await expectLater(
          repo.reauthenticate('x'),
          throwsA(isA<AuthException>()
              .having((e) => e.code, 'code', AuthErrorCode.network)));
    });

    test('reauthenticate: sem usuario, sem e-mail ou sem provedor senha',
        () async {
      await expectLater(
          repo.reauthenticate('x'), throwsA(isA<AuthException>()));
      logged(email: null);
      await expectLater(
          repo.reauthenticate('x'), throwsA(isA<AuthException>()));
      final u = logged()..providers = [FakeUserInfo('google.com')];
      await expectLater(
          repo.reauthenticate('x'),
          throwsA(isA<AuthException>()
              .having((e) => e.code, 'code', AuthErrorCode.unknown)));
      expect(u.reauthCalls, 0);
    });

    test('a excecao nao carrega a senha', () async {
      logged().reauthError = FirebaseAuthException(code: 'wrong-password');
      try {
        await repo.reauthenticate('SENHA-SECRETA');
      } on AuthException catch (e) {
        expect(e.toString(), isNot(contains('SENHA-SECRETA')));
        expect(e.detail, isNull);
      }
    });

    test('deleteAccount chama user.delete', () async {
      final u = logged();
      await repo.deleteAccount();
      expect(u.deleteCalls, 1);
    });

    test('deleteAccount: requires-recent-login vira AuthException', () async {
      logged().deleteError =
          FirebaseAuthException(code: 'requires-recent-login');
      await expectLater(
          repo.deleteAccount(),
          throwsA(isA<AuthException>().having(
              (e) => e.code, 'code', AuthErrorCode.requiresRecentLogin)));
    });

    test('deleteAccount: usuario ja excluido (outro aparelho) e sucesso',
        () async {
      for (final code in ['user-not-found', 'user-token-expired']) {
        logged().deleteError = FirebaseAuthException(code: code);
        await repo.deleteAccount();
        expect(auth.currentUser, isNull); // sessao local encerrada
      }
      auth.setUser(null);
      await repo.deleteAccount(); // sem usuario: nada a fazer
    });
  });
}
