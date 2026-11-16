import 'package:astrum/features/profile/presentation/account_controller.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/recipient_unavailable.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/make_container.dart';

void main() {
  late FakeSocialRepository social;

  setUp(() => social = FakeSocialRepository());

  Future<AccountController> setup({bool loggedIn = true}) async {
    final c = await makeContainer(
      user: loggedIn ? testUser() : null,
      overrides: [socialRepositoryProvider.overrideWithValue(social)],
    );
    addTearDown(c.dispose);
    return c.read(accountControllerProvider.notifier);
  }

  group('addFriendByEmail', () {
    test('email inexistente: mensagem e nada gravado', () async {
      final ctl = await setup();

      final msg = await ctl.addFriendByEmail('nao@existe.com');

      expect(msg, 'Nenhuma constelação encontrada com esse email.');
      expect(social.searchedEmails, ['nao@existe.com']);
      expect(social.addedFriends, isEmpty);
    });

    test('o proprio email: mesma mensagem e nada gravado', () async {
      social.usersByEmail['u1@example.com'] =
          const Friend(id: 'u1', name: 'Eu');
      final ctl = await setup();

      final msg = await ctl.addFriendByEmail('u1@example.com');

      expect(msg, 'Nenhuma constelação encontrada com esse email.');
      expect(social.addedFriends, isEmpty);
    });

    test('sucesso: adiciona e devolve a mensagem com o nome', () async {
      const amiga = Friend(id: 'u2', name: 'Luna');
      social.usersByEmail['luna@example.com'] = amiga;
      final ctl = await setup();

      final msg = await ctl.addFriendByEmail('luna@example.com');

      expect(msg, 'Luna entrou na sua constelação.');
      expect(social.addedFriends.single.uid, 'u1');
      expect(social.addedFriends.single.friend.id, 'u2');
    });

    test('sem perfil nao busca', () async {
      final ctl = await setup(loggedIn: false);

      expect(await ctl.addFriendByEmail('luna@example.com'), isNull);
      expect(social.searchedEmails, isEmpty);
    });
  });

  test('sendIntention repassa remetente, destinatario e intencao', () async {
    final ctl = await setup();

    final text = await ctl.sendIntention(
        testUser(), const Friend(id: 'u2', name: 'Luna'), 'luz', 'Luz');
    expect(text, 'Luz enviada a Luna');

    expect(social.intentions, [
      {
        'fromUid': 'u1',
        'fromName': 'Teste',
        'toUid': 'u2',
        'intentionId': 'luz',
        'intentionLabel': 'Luz',
      }
    ]);
  });

  test('sendIntention a conta excluida: avisa e remove o amigo da lista',
      () async {
    final ctl = await setup();
    social.sendError = const RecipientUnavailableException();

    final text = await ctl.sendIntention(
        testUser(), const Friend(id: 'u2', name: 'Luna'), 'luz', 'Luz');

    expect(text, 'Esta conta não existe mais.');
    expect(social.removedFriends, [(uid: 'u1', friendId: 'u2')]);
    expect(social.intentions, isEmpty);
  });
}
