import 'package:astrum/core/clock/clock_providers.dart';
import 'package:astrum/features/cosmos/presentation/cosmos_screen.dart';
import 'package:astrum/features/economy/presentation/economy_providers.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/make_container.dart';
import '../../../support/pump_screen.dart';

void main() {
  late FakeEconomyRepository economy;

  setUp(() => economy = FakeEconomyRepository());

  Future<void> pump(WidgetTester tester, {String? checkIn}) => pumpScreen(
        tester,
        const CosmosScreen(),
        user: AppUser(
          uid: 'u1',
          email: 'u1@example.com',
          name: 'Teste Silva',
          stardust: 500,
          dailyCheckIn: checkIn,
        ),
        overrides: [
          clockProvider.overrideWithValue(() => testNow),
          economyRepositoryProvider.overrideWithValue(economy),
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
        ],
      );

  testWidgets('mostra a saudacao com o primeiro nome', (tester) async {
    await pump(tester);

    expect(find.text('Olá, Teste'), findsOneWidget);
  });

  testWidgets('toque no check-in mostra o snackbar de sucesso', (tester) async {
    await pump(tester);

    final button = find.text('Check-in diário · +25 Poeira Estelar');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump();

    expect(economy.checkIns, [(uid: 'u1', today: '2026-11-14')]);
    expect(
        find.text('+25 Poeira Estelar pelo check-in de hoje'), findsOneWidget);
  });

  testWidgets('check-in ja feito hoje deixa o botao desabilitado',
      (tester) async {
    await pump(tester, checkIn: '2026-11-14');

    final label = find.text('Check-in de hoje já recebido · 500 ✦');
    expect(label, findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.ancestor(of: label, matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull);
  });
}
