import 'dart:async';

import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/auth/presentation/auth_providers.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/delete_account_screen.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/in_memory_chat_repository.dart';
import '../../../support/pump_screen.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profile;

  Future<void> pump(WidgetTester tester, {bool missing = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    auth = FakeAuthRepository();
    profile = FakeProfileRepository();
    await pumpScreen(
      tester,
      const DeleteAccountScreen(),
      user: testUser(),
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profile),
        chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
        eventsRepositoryProvider.overrideWithValue(FakeEventsRepository()),
        socialRepositoryProvider.overrideWithValue(FakeSocialRepository()),
        analyticsServiceProvider.overrideWithValue(FakeAnalytics()),
        prefsProvider.overrideWithValue(prefs),
        if (missing) ...[
          currentUidProvider.overrideWithValue('u1'),
          profileProvider.overrideWith((ref) => Stream<AppUser?>.value(null)),
        ],
      ],
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder button(String label) => find.widgetWithText(FilledButton, label);

  testWidgets('formulario: texto do que sera apagado; botao so com senha',
      (tester) async {
    await pump(tester);

    expect(find.text('Excluir conta'), findsOneWidget); // titulo
    expect(find.text(deleteAccountBody), findsOneWidget);
    expect(find.text('Digite sua senha para confirmar'), findsOneWidget);
    expect(tester.widget<FilledButton>(button('Excluir minha conta')).onPressed,
        isNull);
    expect(find.text('Sair'), findsNothing);

    await tester.enterText(find.byType(TextField), 'minhasenha');
    await tester.pump();
    expect(tester.widget<FilledButton>(button('Excluir minha conta')).onPressed,
        isNotNull);
  });

  testWidgets('a senha fica oculta no campo', (tester) async {
    await pump(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
  });

  testWidgets('dialogo final: cancelar nao apaga; confirmar executa',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'minhasenha');
    await tester.pump();

    await tester.tap(button('Excluir minha conta'));
    await settle(tester);
    expect(find.text('Excluir a conta definitivamente?'), findsOneWidget);
    expect(find.text('Não será possível desfazer.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(auth.reauthCalls, isEmpty);
    expect(profile.deletedProfiles, isEmpty);

    await tester.tap(button('Excluir minha conta'));
    await settle(tester);
    await tester.tap(find.text('Excluir definitivamente'));
    await settle(tester);

    expect(auth.reauthCalls, ['minhasenha']);
    expect(profile.deletedProfiles, ['u1']);
    expect(auth.deleteAccountCalls, 1);
  });

  testWidgets('progresso: sem voltar, com texto e etapa', (tester) async {
    await pump(tester);
    final gate = Completer<void>();
    auth.completerReauth = gate;
    await tester.enterText(find.byType(TextField), 'minhasenha');
    await tester.pump();
    await tester.tap(button('Excluir minha conta'));
    await settle(tester);
    await tester.tap(find.text('Excluir definitivamente'));
    await settle(tester);

    expect(find.text('Excluindo sua conta… Não feche o app.'), findsOneWidget);
    expect(find.text('Verificando… (1 de 11)'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    final pop = tester.widget<PopScope>(find.byType(PopScope));
    expect(pop.canPop, isFalse);

    gate.complete();
    await settle(tester);
  });

  testWidgets('erro de senha: mensagem, Tentar de novo sem novo dialogo',
      (tester) async {
    await pump(tester);
    auth.reauthError = const AuthException(AuthErrorCode.invalidCredentials);
    await tester.enterText(find.byType(TextField), 'errada');
    await tester.pump();
    await tester.tap(button('Excluir minha conta'));
    await settle(tester);
    await tester.tap(find.text('Excluir definitivamente'));
    await settle(tester);

    expect(find.text('Senha incorreta. Nada foi apagado.'), findsOneWidget);
    expect(button('Tentar de novo'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);
    expect(profile.deletedProfiles, isEmpty);

    auth.reauthError = null;
    await tester.tap(button('Tentar de novo'));
    await settle(tester);
    expect(find.text('Excluir a conta definitivamente?'), findsNothing);
    expect(auth.deleteAccountCalls, 1);
  });

  testWidgets('sem conexao: texto de tentar de novo', (tester) async {
    await pump(tester);
    profile.reachableError = const AuthException(AuthErrorCode.network);
    await tester.enterText(find.byType(TextField), 'minhasenha');
    await tester.pump();
    await tester.tap(button('Excluir minha conta'));
    await settle(tester);
    await tester.tap(find.text('Excluir definitivamente'));
    await settle(tester);

    expect(
        find.text('Sem conexão. Conecte-se e toque em Tentar de novo. '
            'O que já foi apagado continua apagado.'),
        findsOneWidget);
    expect(button('Tentar de novo'), findsOneWidget);
  });

  testWidgets('perfil ausente: texto proprio e botao Sair', (tester) async {
    await pump(tester, missing: true);

    expect(find.text(deleteAccountMissingBody), findsOneWidget);
    expect(find.text(deleteAccountBody), findsNothing);
    expect(find.text('Sair'), findsOneWidget);
  });
}
