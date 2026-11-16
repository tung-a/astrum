import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/social/data/social_repository.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/domain/intention_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final socialRepositoryProvider =
    Provider((ref) => SocialRepository(ref.watch(firestoreProvider)));

/// Todas as relacoes do usuario (amigos, pedidos e lapides): um unico
/// listener. Depende so do uid (nao reabre quando saldo ou perfil mudam).
final friendshipsProvider = StreamProvider<List<Friendship>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(socialRepositoryProvider).watchFriendships(uid);
});

/// As relacoes separadas por papel (amigos, recebidos, enviados, bloqueados).
final friendshipsViewProvider = Provider<AsyncValue<FriendshipsView>>((ref) {
  final uid = ref.watch(currentUidProvider);
  return ref.watch(friendshipsProvider).whenData(
        (list) => uid == null ? const FriendshipsView() : viewFor(uid, list),
      );
});

/// Amigos aceitos (mesmo tipo de antes: `valueOrNull` segue valendo).
final friendsProvider = Provider<AsyncValue<List<Friend>>>(
  (ref) => ref.watch(friendshipsViewProvider).whenData((v) => v.friends),
);

/// Pedidos recebidos aguardando resposta (selo no icone do Perfil).
final incomingRequestCountProvider = Provider<int>((ref) => ref.watch(
    friendshipsViewProvider
        .select((v) => v.valueOrNull?.incoming.length ?? 0)));

/// Nome publico de um uid, para rotular pedidos enviados (o documento ainda
/// nao tem o nome do destinatario). Null se oculto ou excluido.
final publicNameProvider = FutureProvider.family<String?, String>(
    (ref, uid) => ref.watch(socialRepositoryProvider).publicNameOf(uid));

final intentionProvider = StreamProvider<IntentionNotice?>((ref) {
  final uid = ref.watch(currentUidProvider);
  final notificationsEnabled = ref.watch(profileProvider
      .select((p) => p.valueOrNull?.notificationsEnabled ?? false));
  if (uid == null || !notificationsEnabled) return Stream.value(null);
  return ref.watch(socialRepositoryProvider).watchUnreadIntention(uid);
});
