import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/core/theme/astrum_theme.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/rituals/domain/ritual_event.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:astrum/features/social/domain/intention_notice.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monta [screen] com o tema do app, perfil fixo e sem streams do Firestore.
///
/// Spike do passo 0 (etapa 9): `GoogleFonts` nao quebra o widget test (a busca
/// de fonte falha em silencio no ambiente de teste e cai na fonte padrao).
/// `Starfield` anima em loop: use `pump()`/`pump(Duration)`, nunca
/// `pumpAndSettle`. A unica excecao observada e a assercao de debug
/// "ListTile background color or ink splashes may be invisible" (ListTile
/// dentro de um Container colorido, existente na UI de hoje e fora do escopo
/// de uma refatoracao pura): [tolerateListTileInkAssertion] a filtra.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  AppUser? user,
  List<Override> overrides = const [],
}) async {
  tolerateListTileInkAssertion();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileProvider.overrideWith((ref) => Stream<AppUser?>.value(user)),
      currentUidProvider.overrideWithValue(user?.uid),
      eventsProvider
          .overrideWith((ref) => Stream<List<RitualEvent>>.value(const [])),
      intentionProvider
          .overrideWith((ref) => Stream<IntentionNotice?>.value(null)),
      ...overrides,
    ],
    child: MaterialApp(theme: AstrumTheme.dark, home: screen),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Ignora so a assercao de ink do ListTile; qualquer outro erro continua
/// falhando o teste. Restaura o handler no fim do teste.
void tolerateListTileInkAssertion() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains(
        'ListTile background color or ink splashes may be invisible')) {
      return;
    }
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}
