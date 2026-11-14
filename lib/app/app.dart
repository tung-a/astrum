import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/app/router.dart';
import 'package:astrum/core/config/env.dart';
import 'package:astrum/core/theme/astrum_theme.dart';

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
