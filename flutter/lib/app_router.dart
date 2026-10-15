import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/app_providers.dart';
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
import 'screens/shop/shop_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<User?>(FirebaseAuth.instance.currentUser);
  final sub = FirebaseAuth.instance.authStateChanges().listen((user) {
    auth.value = user;
  });
  ref.onDispose(() {
    sub.cancel();
    auth.dispose();
  });

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/login',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.value != null;
      final loc = state.matchedLocation;
      final authRoute = loc == '/login' || loc == '/register' || loc == '/welcome';
      if (!loggedIn && !authRoute) return '/login';
      if (loggedIn && authRoute) return '/app/cosmos';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/welcome',
        builder: (_, state) => WelcomeScreen(
          name: state.uri.queryParameters['name'] ?? '',
          email: state.uri.queryParameters['email'] ?? '',
          password: state.uri.queryParameters['password'] ?? '',
        ),
      ),
      GoRoute(path: '/shop', builder: (_, __) => const ShopScreen()),
      GoRoute(
        path: '/admin',
        builder: (_, __) {
          final profile = ref.read(profileProvider).valueOrNull;
          if (profile?.isAdmin != true) return const AccountScreen();
          return const AdminScreen();
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/app/cosmos', builder: (_, __) => const CosmosScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/app/oracle', builder: (_, __) => const OracleScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/app/rituals', builder: (_, __) => const RitualsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/app/astral', builder: (_, __) => const AstralScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/app/account', builder: (_, __) => const AccountScreen()),
          ]),
        ],
      ),
    ],
  );
});
