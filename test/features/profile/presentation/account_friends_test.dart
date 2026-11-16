import 'package:astrum/features/profile/presentation/account_screen.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/pump_screen.dart';

Friendship _friend(String other, String name) => Friendship(
      id: pairIdOf('u1', other),
      uids: ['u1', other]..sort(),
      requesterUid: 'u1',
      requesterName: 'Teste',
      status: FriendshipStatus.accepted,
      responderName: name,
    );

void main() {
  late FakeSocialRepository social;
  setUp(() => social = FakeSocialRepository());

  Future<void> open(WidgetTester tester, List<Friendship> list) =>
      pumpScreen(tester, const AccountScreen(), user: testUser(), overrides: [
        socialRepositoryProvider.overrideWithValue(social),
        friendshipsProvider.overrideWith((ref) => Stream.value(list)),
      ]);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('enviar pedido: confirma com o nome e so entao envia',
      (tester) async {
    social.usersByEmail['luna@x.com'] = const Friend(id: 'u2', name: 'Luna');
    await open(tester, const []);
    await tester.enterText(find.byType(TextField), 'luna@x.com');
    final send = find.widgetWithText(FilledButton, 'Enviar pedido');
    await tester.scrollUntilVisible(send, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(send);
    await settle(tester);

    expect(find.text('Enviar pedido a Luna?'), findsOneWidget);
    expect(social.requests, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar pedido').last);
    await settle(tester);
    expect(social.requests.single.other, 'u2');
    expect(find.text('Pedido enviado a Luna.'), findsOneWidget);
  });

  testWidgets('cancelar a confirmacao nao envia nada', (tester) async {
    social.usersByEmail['luna@x.com'] = const Friend(id: 'u2', name: 'Luna');
    await open(tester, const []);
    await tester.enterText(find.byType(TextField), 'luna@x.com');
    final send = find.widgetWithText(FilledButton, 'Enviar pedido');
    await tester.scrollUntilVisible(send, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(send);
    await settle(tester);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(social.requests, isEmpty);
  });

  testWidgets('e-mail desconhecido: mensagem generica, sem dialogo',
      (tester) async {
    await open(tester, const []);
    await tester.enterText(find.byType(TextField), 'nao@x.com');
    final send = find.widgetWithText(FilledButton, 'Enviar pedido');
    await tester.scrollUntilVisible(send, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(send);
    await settle(tester);
    expect(find.text('Não foi possível enviar o pedido a esse e-mail.'),
        findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('remover amizade: dialogo explica o bloqueio e confirma',
      (tester) async {
    await open(tester, [_friend('u2', 'Luna')]);
    await tester.scrollUntilVisible(find.text('Luna'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Luna'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // expansao
    final remove = find.text('Remover amizade');
    await tester.scrollUntilVisible(remove, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(remove);
    await settle(tester);

    expect(find.text('Remover Luna?'), findsOneWidget);
    expect(find.textContaining('não poderá pedir amizade de novo'),
        findsOneWidget);
    await tester.tap(find.text('Remover'));
    await settle(tester);

    expect(social.actions, ['remove:u2']);
    expect(find.text('Amizade removida.'), findsOneWidget);
  });

  testWidgets('pedidos recebidos: contador no cartao', (tester) async {
    await open(tester, [
      Friendship(
        id: 'u1_u9',
        uids: const ['u1', 'u9'],
        requesterUid: 'u9',
        requesterName: 'Nove',
        status: FriendshipStatus.pending,
      ),
    ]);
    final card = find.text('Pedidos de amizade (1)');
    await tester.scrollUntilVisible(card, 200,
        scrollable: find.byType(Scrollable).first);
    expect(card, findsOneWidget);
  });
}
