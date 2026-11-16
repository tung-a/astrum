import 'package:astrum/core/storage/local_data_cleaner.dart';
import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/features/auth/presentation/auth_providers.dart';
import 'package:astrum/features/auth/presentation/login_screen.dart';
import 'package:astrum/features/profile/presentation/account_controller.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/make_container.dart';
import '../../../support/pump_screen.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profile;
  late SharedPreferences prefs;

  Future<AccountController> setup() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = FakeAuthRepository();
    profile = FakeProfileRepository();
    final c = await makeContainer(user: testUser(), overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(profile),
      prefsProvider.overrideWithValue(prefs),
    ]);
    addTearDown(c.dispose);
    return c.read(accountControllerProvider.notifier);
  }

  test('logout: drena, encerra a sessao e marca a limpeza do cache', () async {
    final ctl = await setup();
    await ctl.signOut();
    expect(profile.drainCalls, 1);
    expect(auth.signOutCalls, 1);
    expect(prefs.getBool(LocalDataCleaner.pendingKey), isTrue);
  });

  test('logout com escritas que nao drenaram: sai, mas nao marca a limpeza',
      () async {
    final ctl = await setup();
    profile.drained = false;
    await ctl.signOut();
    expect(auth.signOutCalls, 1);
    expect(prefs.getBool(LocalDataCleaner.pendingKey), isNull);
  });

  testWidgets('login: aviso "Sua conta foi excluida." aparece uma vez',
      (tester) async {
    await pumpScreen(tester, const LoginScreen(), overrides: [
      accountDeletedNoticeProvider.overrideWith((ref) => true),
    ]);
    expect(find.text('Sua conta foi excluída.'), findsOneWidget);
  });

  testWidgets('login sem exclusao: sem aviso', (tester) async {
    await pumpScreen(tester, const LoginScreen());
    expect(find.text('Sua conta foi excluída.'), findsNothing);
  });
}
