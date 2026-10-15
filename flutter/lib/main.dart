import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_router.dart';
import 'config/env.dart';
import 'providers/app_providers.dart';
import 'theme/astrum_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  if (Env.hasFirebase) {
    await Firebase.initializeApp(options: Env.firebaseOptions);
  }

  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const AstrumApp(),
    ),
  );
}

class AstrumApp extends ConsumerWidget {
  const AstrumApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Env.hasFirebase) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AstrumTheme.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Configure o Firebase com --dart-define-from-file=.env\n\n'
                'Faltando:\n${Env.missingFirebaseVars.join('\n')}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Astrum',
      debugShowCheckedModeBanner: false,
      theme: AstrumTheme.dark,
      routerConfig: router,
    );
  }
}
