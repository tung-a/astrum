import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final accountControllerProvider =
    NotifierProvider<AccountController, void>(AccountController.new);

/// Constelacao (amigos) e intencoes da tela de conta (sem estado). Os
/// interruptores de preferencias e o signOut seguem na tela (uma linha cada).
class AccountController extends Notifier<void> {
  @override
  void build() {}

  /// Busca [email] e adiciona o viajante. Retorna o texto do snackbar; null
  /// sem perfil. A tela confere `mounted` antes de exibir.
  Future<String?> addFriendByEmail(String email) async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return null;
    final social = ref.read(socialRepositoryProvider);
    final found = await social.findUserByEmail(email);
    if (found == null || found.id == profile.uid) {
      return 'Nenhuma constelação encontrada com esse email.';
    }
    await social.addFriend(profile.uid, found);
    return '${found.name} entrou na sua constelação.';
  }

  Future<void> sendIntention(
      AppUser me, Friend friend, String id, String label) {
    return ref.read(socialRepositoryProvider).sendIntention(
          fromUid: me.uid,
          fromName: me.name,
          toUid: friend.id,
          intentionId: id,
          intentionLabel: label,
        );
  }
}
