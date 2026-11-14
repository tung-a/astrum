import 'dart:async';

import 'package:astrum/features/auth/data/auth_repository.dart';
import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/auth/domain/sign_up_data.dart';
import 'package:astrum/features/profile/data/profile_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

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
}
