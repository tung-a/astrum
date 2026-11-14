import 'package:astrum/app/router.dart';
import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/features/auth/presentation/login_screen.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// ignore: implementation_imports
import 'package:go_router/src/information_provider.dart';

import 'support/fake_firebase.dart';
import 'support/fake_repositories.dart';

void main() {
  testWidgets('sem usuario, rota protegida vai para /login', (tester) async {
    final auth = FakeFirebaseAuth();
    final container = ProviderContainer(overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      ...FakeRepos().overrides,
    ]);
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    router.go('/admin');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(router.state.matchedLocation, '/login');
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  // Limitacao: as telas reais usam FirebaseFirestore.instance e nao podem ser
  // montadas em teste. Por isso o routerProvider real e exercitado pelo parser
  // de rotas do proprio GoRouter (que executa o redirect de verdade), sem
  // construir nenhuma tela.
  Future<(ProviderContainer, BuildContext)> setup(
    WidgetTester tester, {
    required FakeFirebaseAuth auth,
    required String role,
    String uid = 'u1',
  }) async {
    final repos = FakeRepos()..profile.emit(testUser(uid: uid, role: role));
    final container = ProviderContainer(overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      ...repos.overrides,
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SizedBox()),
    ));
    final ctx = tester.element(find.byType(SizedBox));
    // Mantem profileProvider vivo (as telas fariam isso) e o router criado.
    container.listen(profileProvider, (_, __) {});
    container.read(routerProvider);
    await tester.pump();
    await tester.pump();
    return (container, ctx);
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

  testWidgets('admin logado em /login vai para /admin (routerProvider real)',
      (tester) async {
    final (container, ctx) = await setup(tester,
        auth: FakeFirebaseAuth(FakeUser('u1')), role: 'admin');
    expect(await resolve(container, ctx, '/login'), '/admin');
    expect(await resolve(container, ctx, '/admin'), '/admin');
  });

  testWidgets('nao admin em /admin vai para /app/account', (tester) async {
    final (container, ctx) = await setup(tester,
        auth: FakeFirebaseAuth(FakeUser('u1')), role: 'user');
    expect(await resolve(container, ctx, '/admin'), '/app/account');
    expect(await resolve(container, ctx, '/login'), '/app/cosmos');
  });

  test('decideRedirect: admin em /app/ so redireciona fora do loading', () {
    expect(
        decideRedirect(
            loggedIn: true,
            location: '/app/cosmos',
            isAdmin: true,
            isLoading: true),
        isNull);
    expect(
        decideRedirect(
            loggedIn: true,
            location: '/app/cosmos',
            isAdmin: true,
            isLoading: false),
        '/admin');
  });

  testWidgets('troca de admin A para B sem logout: B nao e admin',
      (tester) async {
    final auth = FakeFirebaseAuth(FakeUser('a'));
    final (container, ctx) = await setup(tester,
        auth: auth, role: 'admin', uid: 'a');
    expect(container.read(routerProfileKeyProvider).isAdmin, isTrue);

    auth.setUser(FakeUser('b'));
    await tester.pump();
    await tester.pump();

    // Perfil de B ainda nao chegou: o admin retido de A nao vale.
    expect(container.read(routerProfileKeyProvider).isAdmin, isFalse);

    // Chegou o perfil de B (nao admin): /admin e negado.
    final repo =
        container.read(profileRepositoryProvider) as FakeProfileRepository;
    repo.emit(testUser(uid: 'b'));
    await tester.pump();
    await tester.pump();
    expect(container.read(routerProfileKeyProvider).isAdmin, isFalse);
    expect(await resolve(container, ctx, '/admin'), '/app/account');
  });

  testWidgets('erro no stream de auth e tratado como deslogado',
      (tester) async {
    final auth = FakeFirebaseAuth(FakeUser('u1'));
    final (container, ctx) = await setup(tester, auth: auth, role: 'user');
    expect(await resolve(container, ctx, '/app/cosmos'), '/app/cosmos');

    auth.setError(Exception('falha'));
    await tester.pump();
    await tester.pump();
    expect(await resolve(container, ctx, '/app/cosmos'), '/login');
  });
}
