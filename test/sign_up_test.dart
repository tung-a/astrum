import 'dart:async';

import 'package:astrum/app_router.dart';
import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/auth/presentation/auth_providers.dart';
import 'package:astrum/features/auth/presentation/sign_up_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:go_router/src/information_provider.dart';

import 'support/fake_firebase.dart';
import 'support/fake_repositories.dart';

const _draft =
    SignUpDraft(name: 'Nova', email: 'n@x.com', password: 'segredo123');

Future<bool> _submit(ProviderContainer c) =>
    c.read(signUpControllerProvider.notifier).submit(
        birthDate: '01/01/2000',
        birthTime: '',
        birthPlace: '',
        zodiacSign: 'Aries');

void main() {
  group('SignUpController', () {
    late FakeAuthRepository auth;
    late ProviderContainer c;

    setUp(() {
      auth = FakeAuthRepository();
      c = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(auth)]);
      addTearDown(c.dispose);
    });

    SignUpState st() => c.read(signUpControllerProvider);

    test('start guarda rascunho e clear limpa', () {
      c.read(signUpControllerProvider.notifier).start(_draft);
      expect(st().draft, _draft);
      expect(st().inFlight, isFalse);
      c.read(signUpControllerProvider.notifier).clear();
      expect(st().draft, isNull);
    });

    test('submit mantem inFlight ate terminar; sucesso limpa tudo', () async {
      auth.completer = Completer<void>();
      c.read(signUpControllerProvider.notifier).start(_draft);
      final f = _submit(c);
      await Future<void>.delayed(Duration.zero);
      expect(st().inFlight, isTrue);
      expect(auth.registerCalls.single.password, 'segredo123');
      expect(auth.registerCalls.single.zodiacSign, 'Aries');
      auth.completer!.complete();
      expect(await f, isTrue);
      expect(st().inFlight, isFalse);
      expect(st().draft, isNull);
    });

    test('SignUpDraft.toString mascara a senha', () {
      expect(_draft.toString(), isNot(contains('segredo123')));
      expect(_draft.toString(), contains('***'));
    });

    test('falha preserva o rascunho, solta o flag e relanca', () async {
      auth.failWith = const AuthException(AuthErrorCode.profileCreationFailed);
      c.read(signUpControllerProvider.notifier).start(_draft);
      await expectLater(_submit(c), throwsA(isA<AuthException>()));
      expect(st().inFlight, isFalse);
      expect(st().draft, _draft);
    });

    test('excecao inesperada tambem solta o flag (try/finally)', () async {
      auth.failWith = null;
      final c2 = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(_Explode()),
      ]);
      addTearDown(c2.dispose);
      c2.read(signUpControllerProvider.notifier).start(_draft);
      await expectLater(_submit(c2), throwsStateError);
      expect(c2.read(signUpControllerProvider).inFlight, isFalse);
    });

    test('sem rascunho, submit nao chama o repositorio', () async {
      expect(await _submit(c), isFalse);
      expect(auth.registerCalls, isEmpty);
    });
  });

  group('router e cadastro', () {
    Future<(ProviderContainer, BuildContext, FakeAuthRepository)> setup(
      WidgetTester tester, {
      required FakeFirebaseAuth auth,
      bool withProfile = false,
    }) async {
      final repos = FakeRepos();
      if (withProfile) repos.profile.emit(testUser());
      final fakeAuth = FakeAuthRepository();
      final container = ProviderContainer(overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        authRepositoryProvider.overrideWithValue(fakeAuth),
        ...repos.overrides,
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ));
      final ctx = tester.element(find.byType(SizedBox));
      container.listen(profileProvider, (_, __) {});
      container.read(routerProvider);
      await tester.pump();
      await tester.pump();
      return (container, ctx, fakeAuth);
    }

    Future<String> resolve(
        ProviderContainer container, BuildContext ctx, String location) async {
      final router = container.read(routerProvider);
      final matches = await router.routeInformationParser
          .parseRouteInformationWithDependencies(
              RouteInformation(
                  uri: Uri.parse(location),
                  state: RouteInformationState<void>(type: NavigatingType.go)),
              ctx);
      return matches.uri.path;
    }

    testWidgets('/welcome sem rascunho redireciona para /register',
        (tester) async {
      final (c, ctx, _) = await setup(tester, auth: FakeFirebaseAuth());
      expect(await resolve(c, ctx, '/welcome'), '/register');
    });

    testWidgets('/welcome com rascunho abre', (tester) async {
      final (c, ctx, _) = await setup(tester, auth: FakeFirebaseAuth());
      c.read(signUpControllerProvider.notifier).start(_draft);
      expect(await resolve(c, ctx, '/welcome'), '/welcome');
    });

    testWidgets(
        'inFlight segura o usuario logado em /welcome; ao fim vai a home',
        (tester) async {
      final (c, ctx, fakeAuth) = await setup(tester,
          auth: FakeFirebaseAuth(FakeUser('u1')), withProfile: true);
      // Sem cadastro em andamento, logado em /welcome vai para a home.
      expect(await resolve(c, ctx, '/welcome'), '/app/cosmos');

      fakeAuth.completer = Completer<void>();
      c.read(signUpControllerProvider.notifier).start(_draft);
      final f = _submit(c);
      await tester.pump();
      expect(c.read(routerProfileKeyProvider).isLoading, isTrue);
      expect(await resolve(c, ctx, '/welcome'), '/welcome');

      fakeAuth.completer!.complete();
      await f;
      await tester.pump();
      expect(c.read(routerProfileKeyProvider).isLoading, isFalse);
      expect(await resolve(c, ctx, '/welcome'), '/app/cosmos');
    });

    testWidgets('inFlight solto apos falha (flag nao fica preso)',
        (tester) async {
      final (c, _, fakeAuth) = await setup(tester,
          auth: FakeFirebaseAuth(FakeUser('u1')), withProfile: true);
      fakeAuth.failWith = const AuthException(AuthErrorCode.unknown);
      c.read(signUpControllerProvider.notifier).start(_draft);
      await expectLater(_submit(c), throwsA(isA<AuthException>()));
      await tester.pump();
      expect(c.read(routerProfileKeyProvider).isLoading, isFalse);
    });
  });
}

class _Explode extends FakeAuthRepository {
  @override
  Future<void> register(data) async => throw StateError('inesperado');
}
