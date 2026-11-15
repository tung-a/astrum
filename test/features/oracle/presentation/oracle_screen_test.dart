import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:astrum/features/oracle/presentation/oracle_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/pump_screen.dart';

void main() {
  testWidgets('toque num chip adiciona a mensagem do usuario e a resposta',
      (tester) async {
    final chats = FakeChatRepository();
    final oracle = FakeOracleService(reply: 'Resposta do oraculo');
    await pumpScreen(
      tester,
      const OracleScreen(),
      user: testUser(),
      overrides: [
        chatRepositoryProvider.overrideWithValue(chats),
        oracleServiceProvider.overrideWithValue(oracle),
        analyticsServiceProvider.overrideWithValue(FakeAnalytics()),
      ],
    );
    await tester.pump(); // post-frame: hidrata o historico
    expect(chats.loads, ['u1']);

    await tester.tap(find.text('Previsão para o amor'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Previsão para o amor'), findsOneWidget); // so a mensagem
    expect(find.text('Resposta do oraculo'), findsOneWidget);
    expect(oracle.calls.single.prompt, 'Previsão para o amor');
    expect(chats.saves, hasLength(2));
  });

  testWidgets('falha do oraculo mostra o erro na conversa e libera o envio',
      (tester) async {
    final oracle = FakeOracleService()..failWith = StateError('oraculo fora');
    await pumpScreen(
      tester,
      const OracleScreen(),
      user: testUser(),
      overrides: [
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        oracleServiceProvider.overrideWithValue(oracle),
        analyticsServiceProvider.overrideWithValue(FakeAnalytics()),
      ],
    );
    await tester.pump(); // post-frame: hidrata

    await tester.tap(find.text('Qual cristal usar?'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Não foi possível obter a resposta. Tente novamente.'),
        findsOneWidget);
    expect(find.text('O oráculo consulta as esferas…'), findsNothing);
    final send =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
    expect(send.onPressed, isNotNull);
  });

  testWidgets('prompt pendente vai para o campo de texto e e consumido',
      (tester) async {
    await pumpScreen(
      tester,
      const OracleScreen(),
      user: testUser(),
      overrides: [
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        oracleServiceProvider.overrideWithValue(FakeOracleService(reply: 'ok')),
        analyticsServiceProvider.overrideWithValue(FakeAnalytics()),
        pendingOraclePromptProvider.overrideWith((ref) => 'pergunta pronta'),
      ],
    );
    await tester.pump(); // post-frame: hidrata
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'pergunta pronta');
  });
}
