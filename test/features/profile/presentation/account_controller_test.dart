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

  test('sendIntention a conta excluida: so avisa e mantem o amigo', () async {
    final ctl = await setup();
    social.sendError = const RecipientUnavailableException();

    final text = await ctl.sendIntention(
        testUser(), const Friend(id: 'u2', name: 'Luna'), 'luz', 'Luz');

    expect(text, 'Esta amizade não existe mais.');
    expect(social.intentions, isEmpty);
  });
}
