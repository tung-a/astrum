import 'dart:async';

import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:astrum/features/oracle/presentation/oracle_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/in_memory_chat_repository.dart';
import '../../../support/pump_screen.dart';

/// Repositorio cuja lista de conversas so chega quando o teste libera.
class _GatedRepo extends InMemoryChatRepository {
  final gate = Completer<void>();

  @override
  Stream<List<ChatConversation>> watchConversations(String uid) async* {
    await gate.future;
    yield* super.watchConversations(uid);
  }
}

/// Lista de conversas falha ate [fail] virar false.
class _FlakyRepo extends InMemoryChatRepository {
  bool fail = true;

  @override
  Stream<List<ChatConversation>> watchConversations(String uid) => fail
      ? Stream<List<ChatConversation>>.error(StateError('unavailable'))
      : super.watchConversations(uid);
}

void main() {
  Future<SharedPreferences> prefs({bool noticeSeen = true}) async {
    SharedPreferences.setMockInitialValues(
        {if (noticeSeen) 'astrum.chat.notice.u1': true});
    return SharedPreferences.getInstance();
  }

  Future<void> pumpOracle(
    WidgetTester tester, {
    required InMemoryChatRepository chats,
    required SharedPreferences sp,
    FakeOracleService? oracle,
    List<Override> extra = const [],
  }) async {
    await pumpScreen(
      tester,
      const OracleScreen(),
      user: testUser(),
      overrides: [
        prefsProvider.overrideWithValue(sp),
        chatRepositoryProvider.overrideWithValue(chats),
        oracleServiceProvider
            .overrideWithValue(oracle ?? FakeOracleService(reply: 'Resposta')),
        analyticsServiceProvider.overrideWithValue(FakeAnalytics()),
        ...extra,
      ],
    );
    await tester.pump(); // post-frame: hidrata
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('toque num chip adiciona a mensagem do usuario e a resposta',
      (tester) async {
    final chats = InMemoryChatRepository();
    final oracle = FakeOracleService(reply: 'Resposta do oraculo');
    await pumpOracle(tester, chats: chats, sp: await prefs(), oracle: oracle);

    await tester.tap(find.text('Previsão para o amor'));
    await settle(tester);

    expect(find.text('Previsão para o amor'), findsOneWidget); // so a mensagem
    expect(find.text('Resposta do oraculo'), findsOneWidget);
    expect(oracle.calls.single.prompt, 'Previsão para o amor');
    final list = await chats.watchConversations('u1').first;
    expect(list.single.messageCount, 2);
  });

  testWidgets('falha do oraculo mostra o erro na conversa e libera o envio',
      (tester) async {
    final oracle = FakeOracleService()..failWith = StateError('oraculo fora');
    await pumpOracle(tester,
        chats: InMemoryChatRepository(), sp: await prefs(), oracle: oracle);

    await tester.tap(find.text('Qual cristal usar?'));
    await settle(tester);

    expect(find.text('Não foi possível obter a resposta. Tente novamente.'),
        findsOneWidget);
    expect(find.text('O oráculo consulta as esferas…'), findsNothing);
    final send =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
    expect(send.onPressed, isNotNull);
  });

  testWidgets('prompt pendente vai para o campo de texto e e consumido',
      (tester) async {
    await pumpOracle(tester,
        chats: InMemoryChatRepository(),
        sp: await prefs(),
        extra: [
          pendingOraclePromptProvider.overrideWith((ref) => 'pergunta pronta'),
        ]);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'pergunta pronta');
  });

  testWidgets(
      'BUG-E9-1: texto digitado antes da hidratacao nao e apagado sem enviar',
      (tester) async {
    final chats = _GatedRepo();
    final oracle = FakeOracleService(reply: 'Resposta');
    await pumpOracle(tester, chats: chats, sp: await prefs(), oracle: oracle);

    await tester.enterText(find.byType(TextField), 'Minha pergunta');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Minha pergunta');
    expect(oracle.calls, isEmpty);
    final send =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
    expect(send.onPressed, isNull);
    final chip = tester.widget<ActionChip>(find.byType(ActionChip).first);
    expect(chip.onPressed, isNull);

    chats.gate.complete();
    await settle(tester);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
    await settle(tester);

    expect(oracle.calls.single.prompt, 'Minha pergunta');
    expect(find.text('Resposta'), findsOneWidget);
  });

  testWidgets('conversa cheia mostra o texto do limite', (tester) async {
    final chats = InMemoryChatRepository();
    for (var i = 0; i < 500; i++) {
      await chats.appendMessage('u1',
          convId: 'a',
          message: ChatTurnStored(
              id: 'm$i',
              role: i.isEven ? 'user' : 'model',
              text: 'msg $i',
              createdAt: DateTime(2026, 1, 1).add(Duration(seconds: i))),
          updatedAt: DateTime(2026, 1, 1).add(Duration(seconds: i)),
          title: 'Cheia',
          isNew: i == 0);
    }
    await pumpOracle(tester, chats: chats, sp: await prefs());

    final limit =
        find.text('Esta conversa atingiu o limite. Inicie uma nova conversa.');
    await tester.scrollUntilVisible(limit, 2000,
        scrollable: find.byType(Scrollable).first);
    expect(limit, findsOneWidget);
    final send =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
    expect(send.onPressed, isNull);
  });

  testWidgets('chip nao apaga o texto digitado pelo usuario', (tester) async {
    final oracle = FakeOracleService(reply: 'Resposta');
    await pumpOracle(tester,
        chats: InMemoryChatRepository(), sp: await prefs(), oracle: oracle);

    await tester.enterText(find.byType(TextField), 'rascunho meu');
    await tester.tap(find.text('Previsão para o amor'));
    await settle(tester);

    expect(oracle.calls.single.prompt, 'Previsão para o amor');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'rascunho meu');
  });

  testWidgets('envio pelo campo limpa o texto so quando aceito',
      (tester) async {
    final oracle = FakeOracleService(reply: 'Resposta');
    await pumpOracle(tester,
        chats: InMemoryChatRepository(), sp: await prefs(), oracle: oracle);

    await tester.enterText(find.byType(TextField), 'Minha pergunta');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
    await settle(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(oracle.calls.single.prompt, 'Minha pergunta');
  });

  testWidgets('troca de uid limpa o rascunho do campo', (tester) async {
    final uid = StateProvider<String?>((ref) => 'u1');
    await pumpOracle(tester,
        chats: InMemoryChatRepository(),
        sp: await prefs(),
        extra: [currentUidProvider.overrideWith((ref) => ref.watch(uid))]);
    await tester.enterText(find.byType(TextField), 'segredo de A');

    ProviderScope.containerOf(tester.element(find.byType(TextField)))
        .read(uid.notifier)
        .state = 'u2';
    await tester.pump();
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('prompt pendente com o chat ja hidratado tambem e consumido',
      (tester) async {
    await pumpOracle(tester,
        chats: InMemoryChatRepository(), sp: await prefs());
    final container =
        ProviderScope.containerOf(tester.element(find.byType(TextField)));

    container.read(pendingOraclePromptProvider.notifier).state =
        'vinda de fora';
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'vinda de fora');
    expect(container.read(pendingOraclePromptProvider), isNull);
  });

  testWidgets('falha ao carregar mostra mensagem e "Tentar de novo"',
      (tester) async {
    final chats = _FlakyRepo();
    await pumpOracle(tester, chats: chats, sp: await prefs());
    await tester.pump();

    expect(find.text('Não foi possível carregar o histórico.'), findsOneWidget);

    chats.fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await settle(tester);

    expect(find.text('Não foi possível carregar o histórico.'), findsNothing);
    final send =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
    expect(send.onPressed, isNotNull);
  });

  testWidgets('abrir o oraculo apaga so as chaves antigas astrum.chat.<uid>',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'astrum.chat.u1': '[{"title":"velho"}]',
      'astrum.chat.u2': 'x',
      'astrum.chat.notice.u1': true,
      'astrum.outra': 'fica',
      'astrum.chatty': 'fica',
    });
    final sp = await SharedPreferences.getInstance();
    await pumpOracle(tester, chats: InMemoryChatRepository(), sp: sp);
    await tester.pump();

    expect(sp.getKeys(),
        {'astrum.chat.notice.u1', 'astrum.outra', 'astrum.chatty'});
  });

  group('aviso de privacidade do historico', () {
    const body =
        'As conversas com o oráculo são armazenadas na nuvem (Firebase, região de '
        'São Paulo, southamerica-east1) para sincronizar entre os seus aparelhos. '
        'Elas ficam guardadas até serem apagadas, sem prazo de expiração. Em '
        'breve você poderá apagá-las no app, e elas poderão ser apagadas junto '
        'com a sua conta.';

    testWidgets('aparece antes do 1o envio, uma unica vez por uid',
        (tester) async {
      final sp = await prefs(noticeSeen: false);
      final oracle = FakeOracleService(reply: 'Resposta');
      await pumpOracle(tester,
          chats: InMemoryChatRepository(), sp: sp, oracle: oracle);

      await tester.tap(find.text('Previsão para o amor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(body), findsOneWidget);
      expect(oracle.calls, isEmpty); // nada enviado antes do "Entendi"

      await tester.tap(find.text('Entendi'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(body), findsNothing);
      expect(sp.getBool('astrum.chat.notice.u1'), isTrue);
      expect(oracle.calls.single.prompt, 'Previsão para o amor');

      // Segundo envio: sem aviso.
      await tester.enterText(find.byType(TextField), 'Outra pergunta');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
      await settle(tester);
      expect(find.text(body), findsNothing);
      expect(oracle.calls, hasLength(2));
    });

    testWidgets('ja visto: nao aparece', (tester) async {
      await pumpOracle(tester,
          chats: InMemoryChatRepository(), sp: await prefs());

      await tester.tap(find.text('Previsão para o amor'));
      await settle(tester);

      expect(find.text(body), findsNothing);
    });
  });
}
