import 'package:astrum/features/profile/presentation/account_screen.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/pump_screen.dart';

class _FailPublicProfile extends FakeProfileRepository {
  @override
  Future<void> setPublicProfile(String uid, bool enabled) async =>
      throw StateError('offline');
}

void main() {
  testWidgets('interruptor de busca: falha mostra snackbar e reverte a UI',
      (tester) async {
    await pumpScreen(
      tester,
      const AccountScreen(),
      user: testUser(),
      overrides: [
        profileRepositoryProvider.overrideWithValue(_FailPublicProfile()),
      ],
    );
    final sw =
        find.widgetWithText(SwitchListTile, 'Aparecer na busca de amigos');
    await tester.scrollUntilVisible(sw, 200,
        scrollable: find.byType(Scrollable).first);
    final before = tester.widget<SwitchListTile>(sw).value;

    await tester.tap(sw);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
        find.text('Não foi possível salvar. Tente de novo.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(sw).value, before);
  });
}
