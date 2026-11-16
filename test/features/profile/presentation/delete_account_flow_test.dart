import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/auth/presentation/auth_providers.dart';
import 'package:astrum/features/oracle/data/chat_repository.dart';
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

/// Conversas falham com ChatOfflineException nas N primeiras chamadas e
/// depois funcionam (simula queda de rede no meio da cascata).
class _FailChatTimes extends InMemoryChatRepository {
  _FailChatTimes(this.failures);
  int failures;

  @override
  Future<List<String>> deleteAllConversations(String uid) async {
    if (failures > 0) {
      failures--;
      throw const ChatOfflineException();
    }
    return super.deleteAllConversations(uid);
  }
}

const _offlinePartial = 'Sem conexão. Conecte-se e toque em Tentar de novo. '
    'O que já foi apagado continua apagado.';
const _recentLogin = 'Por segurança, digite sua senha novamente para concluir.';

/// Fluxo ponta a ponta da tela de exclusao de conta (widget). Complementa
/// `delete_account_screen_test.dart` (formulario, cancelar, erro de senha) com:
/// falha no meio + "Tentar de novo", reautenticacao exigida no fim e perfil
/// ausente concluindo a exclusao pela mesma tela.
void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profile;

  Future<void> pump(
    WidgetTester tester, {
    bool missing = false,
    InMemoryChatRepository? chat,
  }) async {
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
        chatRepositoryProvider
            .overrideWithValue(chat ?? InMemoryChatRepository()),
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

  /// Digita a senha, toca em "Excluir minha conta" e confirma no dialogo final.
  Future<void> enterAndConfirm(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextField), password);
    await tester.pump();
    await tester.tap(button('Excluir minha conta'));
    await settle(tester);
    await tester.tap(find.text('Excluir definitivamente'));
    await settle(tester);
  }

  testWidgets(
      'falha no meio (conversas sem conexao): mostra o que ficou apagado e '
      '"Tentar de novo" conclui', (tester) async {
    await pump(tester, chat: _FailChatTimes(1));
    await enterAndConfirm(tester, 'minhasenha');

    expect(find.text(_offlinePartial), findsOneWidget);
    expect(button('Tentar de novo'), findsOneWidget);
    expect(profile.deletedProfiles, ['u1']);
    expect(auth.deleteAccountCalls, 0); // Auth so no fim da cascata

    await tester.tap(button('Tentar de novo'));
    await settle(tester);

    expect(find.text(_offlinePartial), findsNothing);
    expect(auth.reauthCalls, ['minhasenha', 'minhasenha']);
    expect(auth.deleteAccountCalls, 1);
  });

  testWidgets(
      'reautenticacao exigida no fim: pede a senha de novo e so repete a '
      'conta Auth (Firestore nao e refeito)', (tester) async {
    await pump(tester);
    auth.deleteAccountError =
        const AuthException(AuthErrorCode.requiresRecentLogin);
    await enterAndConfirm(tester, 'minhasenha');

    expect(find.text(_recentLogin), findsOneWidget);
    expect(button('Tentar de novo'), findsOneWidget);
    expect(profile.deletedProfiles, ['u1']);

    auth.deleteAccountError = null;
    await tester.tap(button('Tentar de novo'));
    await settle(tester);

    expect(find.text(_recentLogin), findsNothing);
    expect(auth.deleteAccountCalls, 2);
    expect(profile.deletedProfiles, ['u1']); // nao apagou de novo
  });

  testWidgets('perfil ausente: a exclusao conclui pela mesma tela',
      (tester) async {
    await pump(tester, missing: true);
    expect(find.text(deleteAccountMissingBody), findsOneWidget);

    await enterAndConfirm(tester, 'minhasenha');

    expect(profile.deletedProfiles, ['u1']);
    expect(auth.reauthCalls, ['minhasenha']);
    expect(auth.deleteAccountCalls, 1);
    expect(find.text('Tentar de novo'), findsNothing);
  });
}
