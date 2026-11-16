import 'dart:async';

import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/presentation/friend_requests_screen.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/pump_screen.dart';

Friendship _f(String other,
        {String requester = 'u1',
        FriendshipStatus status = FriendshipStatus.pending,
        String? responderName,
        String? declinedBy}) =>
    Friendship(
      id: pairIdOf('u1', other),
      uids: ['u1', other]..sort(),
      requesterUid: requester,
      requesterName: 'Nome $other',
      status: status,
      responderName: responderName,
      declinedBy: declinedBy,
    );

void main() {
  late FakeSocialRepository social;
  setUp(() => social = FakeSocialRepository());

  Future<void> open(WidgetTester tester, Override friendships) =>
      pumpScreen(tester, const FriendRequestsScreen(),
          user: testUser(),
          overrides: [
            socialRepositoryProvider.overrideWithValue(social),
            friendships,
          ]);

  Override data(List<Friendship> l) =>
      friendshipsProvider.overrideWith((ref) => Stream.value(l));

  testWidgets('carregando: mostra o indicador', (tester) async {
    final never = StreamController<List<Friendship>>();
    addTearDown(never.close);
    await open(tester, friendshipsProvider.overrideWith((ref) => never.stream));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('vazio: texto orientando', (tester) async {
    await open(tester, data(const []));
    expect(find.text(requestsEmptyText), findsOneWidget);
    expect(find.text('Aceitar'), findsNothing);
  });

  testWidgets('erro: mensagem e "Tentar de novo" reabre a consulta',
      (tester) async {
    var calls = 0;
    await open(
      tester,
      friendshipsProvider.overrideWith((ref) {
        calls++;
        return calls == 1
            ? Stream<List<Friendship>>.error(StateError('x'))
            : Stream.value([_f('u2', requester: 'u2')]);
      }),
    );
    expect(find.text(requestsLoadErrorText), findsOneWidget);
    await tester.tap(find.text('Tentar de novo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(requestsLoadErrorText), findsNothing);
    expect(find.text('Nome u2'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('recebido: aceitar chama o controller e mostra o texto',
      (tester) async {
    await open(tester, data([_f('u2', requester: 'u2')]));
    expect(find.text('Nome u2'), findsOneWidget);
    expect(find.text('quer entrar na sua constelação'), findsOneWidget);

    await tester.tap(find.text('Aceitar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(social.actions, ['accept:u2']);
    expect(find.text('Nome u2 entrou na sua constelação.'), findsOneWidget);
  });

  testWidgets('recebido: recusar', (tester) async {
    await open(tester, data([_f('u2', requester: 'u2')]));
    await tester.tap(find.text('Recusar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(social.actions, ['decline:u2']);
    expect(find.text('Pedido recusado.'), findsOneWidget);
  });

  testWidgets('falha ao aceitar: texto neutro e botoes voltam', (tester) async {
    social.actionOutcome = ActionOutcome.gone;
    await open(tester, data([_f('u2', requester: 'u2')]));
    await tester.tap(find.text('Aceitar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Esta amizade não existe mais.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Aceitar'))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'enviado: todos iguais (aguardando + cancelar); cancelar o recusado '
      'em silencio so esconde, sem tocar o servidor', (tester) async {
    social.publicNames['u3'] = 'Cris';
    await open(
        tester,
        data([
          _f('u3'),
          _f('u4', status: FriendshipStatus.declined, declinedBy: 'u4'),
        ]));
    expect(find.text('Cris'), findsOneWidget);
    expect(find.text('Viajante'), findsOneWidget); // sem nome publico
    expect(find.text('Aguardando resposta'), findsNWidgets(2));
    expect(find.text('Cancelar pedido'), findsNWidgets(2));
    expect(find.text('Enviados (2)'), findsOneWidget);

    await tester.tap(find.text('Cancelar pedido').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(social.actions, isEmpty);
    expect(find.text('Pedido cancelado.'), findsOneWidget);
    expect(find.text('Viajante'), findsNothing);
    expect(find.text('Enviados (1)'), findsOneWidget);

    await tester.tap(find.text('Cancelar pedido'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(social.actions, ['cancel:u3']);
  });

  testWidgets('recusados e removidos: desbloquear', (tester) async {
    await open(
        tester,
        data([
          _f('u5',
              requester: 'u5',
              status: FriendshipStatus.declined,
              declinedBy: 'u1'),
        ]));
    expect(find.text('Recusados e removidos'), findsOneWidget);
    expect(find.text('Nome u5'), findsOneWidget);
    await tester.tap(find.text('Desbloquear'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(social.actions, ['unblock:u5']);
  });
}
