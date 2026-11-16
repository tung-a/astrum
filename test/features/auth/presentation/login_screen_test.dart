import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/auth/presentation/auth_providers.dart';
import 'package:astrum/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/pump_screen.dart';

void main() {
  late FakeAuthRepository auth;

  Future<void> pump(WidgetTester tester) async {
    auth = FakeAuthRepository();
    await pumpScreen(tester, const LoginScreen(), overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      analyticsServiceProvider.overrideWithValue(FakeAnalytics()),
    ]);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('esqueci minha senha sem e-mail: pede o e-mail', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Esqueci minha senha'));
    await settle(tester);
    expect(find.text(passwordResetNeedsEmailMessage), findsOneWidget);
    expect(auth.resetEmails, isEmpty);
  });

  testWidgets('esqueci minha senha: envia e mostra aviso neutro',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'luna@x.com');
    await tester.tap(find.text('Esqueci minha senha'));
    await settle(tester);
    expect(auth.resetEmails, ['luna@x.com']);
    expect(find.text(passwordResetSentMessage), findsOneWidget);
  });

  testWidgets('esqueci minha senha: erro de rede aparece', (tester) async {
    await pump(tester);
    auth.resetError = const AuthException(AuthErrorCode.network);
    await tester.enterText(find.byType(TextField).first, 'luna@x.com');
    await tester.tap(find.text('Esqueci minha senha'));
    await settle(tester);
    expect(
        find.text('Sem conexão. Conecte-se e tente de novo.'), findsOneWidget);
    expect(find.text(passwordResetSentMessage), findsNothing);
  });
}
