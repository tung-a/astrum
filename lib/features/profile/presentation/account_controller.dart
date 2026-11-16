import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/features/auth/presentation/auth_providers.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/recipient_unavailable.dart';
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

  /// Envia a intencao e devolve o texto do snackbar. Se a conta do amigo foi
  /// excluida, remove-o da propria lista (limpeza preguicosa).
  Future<String> sendIntention(
      AppUser me, Friend friend, String id, String label) async {
    final social = ref.read(socialRepositoryProvider);
    try {
      await social.sendIntention(
        fromUid: me.uid,
        fromName: me.name,
        toUid: friend.id,
        intentionId: id,
        intentionLabel: label,
      );
      return '$label enviada a ${friend.name}';
    } on RecipientUnavailableException {
      try {
        await social.removeFriend(me.uid, friend.id);
      } catch (_) {}
      return 'Esta conta não existe mais.';
    }
  }

  /// Sair: drena as escritas pendentes (ate 5 s), encerra a sessao e marca a
  /// limpeza do cache do Firestore para a proxima partida a frio. Se as
  /// escritas nao drenaram (offline) o cache fica e as pendencias sobrevivem.
  Future<void> signOut() async {
    var drained = false;
    try {
      drained = await ref.read(profileRepositoryProvider).drainPendingWrites();
    } catch (_) {}
    await ref.read(authRepositoryProvider).signOut();
    if (drained) {
      try {
        await ref.read(localDataCleanerProvider).markCacheWipePending();
      } catch (_) {}
    }
  }
}
