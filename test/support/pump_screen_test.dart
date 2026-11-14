import 'package:astrum/features/cosmos/presentation/cosmos_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repositories.dart';
import 'pump_screen.dart';

void main() {
  testWidgets('spike: tela com GoogleFonts e Starfield monta com pump()',
      (tester) async {
    await pumpScreen(tester, const CosmosScreen(), user: testUser());
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Olá, Teste'), findsOneWidget);
  });
}
