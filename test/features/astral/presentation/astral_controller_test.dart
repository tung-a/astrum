import 'package:astrum/core/astro/natal_chart.dart';
import 'package:astrum/features/astral/presentation/astral_controller.dart';
import 'package:astrum/features/astral/presentation/astral_screen.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/make_container.dart';
import '../../../support/pump_screen.dart';

AppUser _user({String birthDate = '05/03/1990', String birthTime = '14:30'}) =>
    AppUser(
      uid: 'u1',
      email: 'u1@example.com',
      name: 'Teste',
      zodiacSign: 'Peixes',
      birthDate: birthDate,
      birthTime: birthTime,
      birthPlace: 'Sao Paulo',
    );

void main() {
  test('calculate grava o mapa calculado do nascimento e retorna true',
      () async {
    final repo = FakeProfileRepository();
    final c = await makeContainer(
        overrides: [profileRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    final user = _user();

    final ok = await c.read(astralControllerProvider.notifier).calculate(user);

    expect(ok, isTrue);
    expect(repo.astralMaps, hasLength(1));
    expect(repo.astralMaps.single.uid, 'u1');
    final expected = computeNatalChart(
        birth: DateTime(1990, 3, 5, 14, 30), birthPlace: 'Sao Paulo');
    expect(AppUser.encodeAstralMap(repo.astralMaps.single.chart),
        AppUser.encodeAstralMap(expected));
  });

  test('data invalida retorna false e nao grava', () async {
    final repo = FakeProfileRepository();
    final c = await makeContainer(
        overrides: [profileRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);

    final ok = await c
        .read(astralControllerProvider.notifier)
        .calculate(_user(birthDate: ''));

    expect(ok, isFalse);
    expect(repo.astralMaps, isEmpty);
  });

  testWidgets('data vazia mostra o snackbar e nao grava', (tester) async {
    final repo = FakeProfileRepository();
    await pumpScreen(tester, const AstralScreen(),
        user: _user(birthDate: ''),
        overrides: [profileRepositoryProvider.overrideWithValue(repo)]);

    await tester.tap(find.text('Calcular mapa no dispositivo'));
    await tester.pump();
    await tester.pump();

    expect(
        find.text('Preencha a data de nascimento na conta.'), findsOneWidget);
    expect(repo.astralMaps, isEmpty);
  });

  testWidgets('data valida grava o mapa pelo repositorio', (tester) async {
    final repo = FakeProfileRepository();
    await pumpScreen(tester, const AstralScreen(),
        user: _user(),
        overrides: [profileRepositoryProvider.overrideWithValue(repo)]);

    await tester.tap(find.text('Calcular mapa no dispositivo'));
    await tester.pump();

    expect(repo.astralMaps, hasLength(1));
    expect(find.text('Preencha a data de nascimento na conta.'), findsNothing);
  });
}
