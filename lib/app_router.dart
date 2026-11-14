import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/firebase/firebase_providers.dart';
import 'providers/app_providers.dart';
import 'providers/sign_up_provider.dart';
import 'screens/account/account_screen.dart';
import 'screens/admin/admin_screen.dart';
import 'screens/astral/astral_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/chat/oracle_screen.dart';
import 'screens/home/cosmos_screen.dart';
import 'screens/rituals/rituals_screen.dart';
import 'screens/shell/main_shell.dart';
import 'screens/shop/inventory_screen.dart';
import 'screens/shop/shop_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Unico trecho do perfil que o redirect consome. Mudancas de saldo,
/// horoscopo etc. nao alteram este valor e nao reavaliam o redirect.
typedef RouterProfileKey = ({bool isAdmin, bool isLoading});

final routerProfileKeyProvider = Provider<RouterProfileKey>((ref) {
  final uid = ref.watch(currentUidProvider);
  // Cadastro em andamento conta como loading: createUser... ja loga o usuario
  // e o router nao pode trocar de tela antes do createProfile/rollback.
  final signUpInFlight =
      ref.watch(signUpControllerProvider.select((s) => s.inFlight));
  final key = ref.watch(profileProvider.select((p) {
    final profile = p.valueOrNull;
    // Perfil retido de outro usuario (troca A -> B) nao vale como admin.
    final isAdmin = profile != null && profile.uid == uid && profile.isAdmin;
    return (isAdmin: isAdmin, isLoading: p.isLoading);
  }));
  return (isAdmin: key.isAdmin, isLoading: key.isLoading || signUpInFlight);
});

/// Decisao de redirect, pura para ser testavel.
String? decideRedirect({
  required bool loggedIn,
  required String location,
  required bool isAdmin,
  required bool isLoading,
}) {
  final authRoute =
      location == '/login' || location == '/register' || location == '/welcome';

  if (!loggedIn && !authRoute) return '/login';
  if (loggedIn && authRoute && !isLoading) {
    return isAdmin ? '/admin' : '/app/cosmos';
  }
  if (loggedIn && location == '/admin' && isLoading) return null;
  if (loggedIn && location == '/admin' && !isAdmin) return '/app/account';
  if (loggedIn && !isLoading && isAdmin && location.startsWith('/app/')) {
    return '/admin';
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  // Seed sincrono com o usuario atual; depois acompanha authStateProvider,
  // que e a unica fonte de authStateChanges do app (profileProvider tambem
  // deriva dele, sem abrir outra assinatura).
  final auth = ValueNotifier<User?>(ref.read(firebaseAuthProvider).currentUser);
  final profileRefresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, next) {
    // Erro no stream de auth e tratado como deslogado.
    if (next.hasError) {
      auth.value = null;
    } else if (next.hasValue) {
      auth.value = next.requireValue;
    }
  });
  ref.listen(routerProfileKeyProvider, (_, __) => profileRefresh.value++);
  ref.onDispose(() {
    auth.dispose();
    profileRefresh.dispose();
  });

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/login',
    refreshListenable: Listenable.merge([auth, profileRefresh]),
    redirect: (context, state) {
      final key = ref.read(routerProfileKeyProvider);
      return decideRedirect(
        loggedIn: auth.value != null,
        location: state.matchedLocation,
        isAdmin: key.isAdmin,
        isLoading: key.isLoading,
      );
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/welcome',
        // Sem rascunho em memoria (processo morto, link direto) volta ao
        // cadastro. Logado e tratado pelo redirect global.
        redirect: (_, __) {
          final s = ref.read(signUpControllerProvider);
          return auth.value == null && s.draft == null && !s.inFlight
              ? '/register'
              : null;
        },
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(path: '/shop', builder: (_, __) => const ShopScreen()),
      GoRoute(path: '/inventory', builder: (_, __) => const InventoryScreen()),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/app/cosmos', builder: (_, __) => const CosmosScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/app/oracle', builder: (_, __) => const OracleScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/app/rituals',
                builder: (_, __) => const RitualsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/app/astral', builder: (_, __) => const AstralScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/app/account',
                builder: (_, __) => const AccountScreen()),
          ]),
        ],
      ),
    ],
  );
});
