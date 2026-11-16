import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Textos que o usuario ve (snackbars). Nenhum leva e-mail, senha ou texto de
/// conversa. A mesma frase generica cobre e-mail inexistente, busca desligada,
/// recusa/remocao anterior e conta excluida (nao vaza o motivo).
const friendRequestGeneric = 'Não foi possível enviar o pedido a esse e-mail.';
const friendRequestTooMany = 'Você já tem muitos pedidos aguardando resposta.';
const friendAlreadySent = 'Você já enviou um pedido a essa pessoa.';
const friendBlockedByMe =
    'Você recusou ou removeu essa pessoa. Desbloqueie em Pedidos de amizade.';
const friendRequestCancelled = 'Pedido cancelado.';
const friendAlreadyFriends = 'Vocês já são amigos.';
const friendCrossAccepted = 'Pedido cruzado: vocês agora são amigos.';
const friendshipGone = 'Esta amizade não existe mais.';
const friendOffline = 'Sem conexão. Tente de novo quando estiver online.';
const friendFailed = 'Não foi possível concluir. Tente de novo.';

/// Resultado da busca por e-mail antes de confirmar o pedido: [friend] para
/// confirmar, ou [message] para mostrar.
class FriendLookup {
  const FriendLookup.found(Friend this.friend) : message = null;
  const FriendLookup.blocked(String this.message) : friend = null;

  final Friend? friend;
  final String? message;
}

final friendshipControllerProvider =
    NotifierProvider<FriendshipController, void>(FriendshipController.new);

/// Pedir, aceitar, recusar, remover, cancelar e desbloquear amizades. Cada
/// metodo devolve o texto do snackbar; a tela confere `mounted`.
class FriendshipController extends Notifier<void> {
  @override
  void build() {}

  ({String uid, String name})? get _me {
    final p = ref.read(profileProvider).valueOrNull;
    return p == null ? null : (uid: p.uid, name: p.name);
  }

  static bool _isOffline(Object e) =>
      e is FirebaseException &&
      (e.code == 'unavailable' || e.code == 'deadline-exceeded');

  /// Texto de erro sem detalhe tecnico (nunca a excecao crua).
  static String _errorText(Object e) =>
      _isOffline(e) ? friendOffline : friendFailed;

  /// Procura o viajante e confere o que da para conferir antes de confirmar.
  Future<FriendLookup> lookup(String email) async {
    final me = _me;
    if (me == null) return const FriendLookup.blocked(friendFailed);
    if (email.trim().isEmpty) {
      return const FriendLookup.blocked('Digite o e-mail de um viajante.');
    }
    final view = ref.read(friendshipsViewProvider).valueOrNull;
    if ((view?.pendingOutgoingCount ?? 0) >= maxPendingOutgoingClient) {
      return const FriendLookup.blocked(friendRequestTooMany);
    }
    try {
      final found =
          await ref.read(socialRepositoryProvider).findUserByEmail(email);
      if (found == null || found.id == me.uid) {
        return const FriendLookup.blocked(friendRequestGeneric);
      }
      if (view != null) {
        if (view.friends.any((f) => f.id == found.id)) {
          return const FriendLookup.blocked(friendAlreadyFriends);
        }
        // So quando o bloqueio e meu: o outro lado nunca fica sabendo.
        if (view.blockedByMe.any((f) => f.otherUid(me.uid) == found.id)) {
          return const FriendLookup.blocked(friendBlockedByMe);
        }
        if (view.outgoing.any((f) => f.otherUid(me.uid) == found.id)) {
          return const FriendLookup.blocked(friendAlreadySent);
        }
      }
      return FriendLookup.found(found);
    } catch (e) {
      return FriendLookup.blocked(_errorText(e));
    }
  }

  /// Envia o pedido a [friend] (ja confirmado pelo usuario).
  Future<String> sendRequest(Friend friend) async {
    final me = _me;
    if (me == null) return friendFailed;
    try {
      final r = await ref.read(socialRepositoryProvider).requestFriendship(
            me: me.uid,
            myName: me.name,
            other: friend.id,
          );
      return switch (r) {
        RequestOutcome.sent => 'Pedido enviado a ${friend.name}.',
        RequestOutcome.crossAccepted => friendCrossAccepted,
        RequestOutcome.alreadySent => friendAlreadySent,
        RequestOutcome.alreadyFriends => friendAlreadyFriends,
        RequestOutcome.unavailable => friendRequestGeneric,
      };
    } catch (e) {
      return _errorText(e);
    }
  }

  Future<String> accept(Friendship f) => _run(
        f,
        (me, other) => ref
            .read(socialRepositoryProvider)
            .acceptFriendship(me: me.uid, myName: me.name, other: other),
        '${f.requesterName} entrou na sua constelação.',
      );

  Future<String> decline(Friendship f) => _run(
        f,
        (me, other) => ref
            .read(socialRepositoryProvider)
            .declineFriendship(me: me.uid, other: other),
        'Pedido recusado.',
      );

  Future<String> remove(Friend friend) async {
    final me = _me;
    if (me == null) return friendFailed;
    return _guard(
      () => ref
          .read(socialRepositoryProvider)
          .removeFriendship(me: me.uid, other: friend.id),
      'Amizade removida.',
    );
  }

  /// Todo pedido enviado e tratado igual: um pedido recusado em silencio (que
  /// o remetente ve como pendente) nao toca o servidor e responde o mesmo texto,
  /// para a interface nao revelar a recusa.
  Future<String> cancel(Friendship f) async {
    if (f.status != FriendshipStatus.pending) return friendRequestCancelled;
    final text = await _run(
      f,
      (me, other) => ref
          .read(socialRepositoryProvider)
          .cancelRequest(me: me.uid, other: other),
      friendRequestCancelled,
    );
    // Recusado entre o toque e a escrita: mesma resposta, sem "nao existe mais".
    return text == friendshipGone ? friendRequestCancelled : text;
  }

  Future<String> unblock(Friendship f) => _run(
        f,
        (me, other) => ref
            .read(socialRepositoryProvider)
            .unblock(me: me.uid, other: other),
        'Desbloqueado. Você pode buscar essa pessoa de novo.',
      );

  Future<String> _run(
    Friendship f,
    Future<ActionOutcome> Function(({String uid, String name}) me, String other)
        op,
    String doneText,
  ) async {
    final me = _me;
    if (me == null) return friendFailed;
    return _guard(() => op(me, f.otherUid(me.uid)), doneText);
  }

  Future<String> _guard(
      Future<ActionOutcome> Function() op, String doneText) async {
    try {
      final r = await op();
      return r == ActionOutcome.done ? doneText : friendshipGone;
    } catch (e) {
      return _errorText(e);
    }
  }
}
