import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/features/social/domain/friend.dart';

/// Id do documento de amizade do par: menor uid + separador + maior uid
/// (comparacao lexicografica, como em `pairId` de firestore.rules).
String pairIdOf(String a, String b) => a.compareTo(b) < 0
    ? '$a$friendshipIdSeparator$b'
    : '$b$friendshipIdSeparator$a';

enum FriendshipStatus {
  pending(friendshipPending),
  accepted(friendshipAccepted),
  declined(friendshipDeclined);

  const FriendshipStatus(this.wire);

  /// Valor gravado em `friendships/{pairId}.status`.
  final String wire;

  static FriendshipStatus? parse(Object? raw) {
    for (final s in values) {
      if (s.wire == raw) return s;
    }
    return null;
  }
}

/// Resultado de pedir amizade (`SocialRepository.requestFriendship`).
enum RequestOutcome {
  /// Pedido criado (pendente).
  sent,

  /// O outro lado ja tinha pedido: virou amizade na hora.
  crossAccepted,

  /// Ja existe um pedido meu (inclusive o recusado em silencio).
  alreadySent,
  alreadyFriends,

  /// Nao foi possivel (recusa/remocao anterior, busca desligada, conta
  /// excluida): a mesma resposta para todos os casos, sem vazar o motivo.
  unavailable,
}

/// Resultado de aceitar, recusar, remover, cancelar ou desbloquear.
enum ActionOutcome {
  /// Feito (ou ja estava feito: idempotente).
  done,

  /// A relacao nao esta mais no estado esperado ("Esta amizade nao existe
  /// mais").
  gone,
}

/// Um documento `friendships/{pairId}`: a relacao entre duas pessoas.
class Friendship {
  const Friendship({
    required this.id,
    required this.uids,
    required this.requesterUid,
    required this.requesterName,
    required this.status,
    this.responderName,
    this.declinedBy,
  });

  /// Le o documento; devolve null se o formato nao for o esperado (nunca
  /// quebra a lista inteira por causa de um documento estranho).
  static Friendship? fromData(String id, Map<String, dynamic> data) {
    final uids = data['uids'];
    final status = FriendshipStatus.parse(data['status']);
    final requester = data['requesterUid'];
    if (uids is! List ||
        uids.length != 2 ||
        uids.any((u) => u is! String) ||
        status == null ||
        requester is! String ||
        !uids.contains(requester)) {
      return null;
    }
    final name = data['requesterName'];
    final responder = data['responderName'];
    final declinedBy = data['declinedBy'];
    return Friendship(
      id: id,
      uids: [uids[0] as String, uids[1] as String],
      requesterUid: requester,
      requesterName: name is String && name.isNotEmpty ? name : 'Viajante',
      status: status,
      responderName:
          responder is String && responder.isNotEmpty ? responder : null,
      declinedBy: declinedBy is String ? declinedBy : null,
    );
  }

  final String id;
  final List<String> uids;
  final String requesterUid;
  final String requesterName;
  final FriendshipStatus status;

  /// So existe depois de um aceite.
  final String? responderName;

  /// Quem recusou ou removeu (so com `status == declined`).
  final String? declinedBy;

  bool isRequester(String me) => requesterUid == me;

  String otherUid(String me) => uids[0] == me ? uids[1] : uids[0];

  /// Nome do outro lado, ou null quando o documento ainda nao o carrega (o
  /// remetente de um pedido pendente nao sabe o nome ate o aceite).
  String? otherName(String me) =>
      isRequester(me) ? responderName : requesterName;
}

/// A lista de relacoes de [uid] separada por papel (funcao pura).
class FriendshipsView {
  const FriendshipsView({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.blockedByMe = const [],
  });

  /// Amizades aceitas, em ordem alfabetica.
  final List<Friend> friends;

  /// Pedidos que recebi e ainda nao respondi.
  final List<Friendship> incoming;

  /// Pedidos que enviei: pendentes (canceláveis) e, em silencio, os recusados
  /// pelo outro lado (o remetente nao e avisado da recusa).
  final List<Friendship> outgoing;

  /// Relacoes que EU recusei ou removi (posso desbloquear).
  final List<Friendship> blockedByMe;

  /// Pedidos enviados ainda realmente pendentes (cota do cliente).
  int get pendingOutgoingCount =>
      outgoing.where((f) => f.status == FriendshipStatus.pending).length;
}

FriendshipsView viewFor(String uid, Iterable<Friendship> list) {
  final friends = <Friend>[];
  final incoming = <Friendship>[];
  final outgoing = <Friendship>[];
  final blocked = <Friendship>[];
  for (final f in list) {
    if (!f.uids.contains(uid)) continue;
    switch (f.status) {
      case FriendshipStatus.accepted:
        friends.add(Friend(
          id: f.otherUid(uid),
          name: f.otherName(uid) ?? 'Viajante',
        ));
      case FriendshipStatus.pending:
        (f.isRequester(uid) ? outgoing : incoming).add(f);
      case FriendshipStatus.declined:
        if (f.declinedBy == uid) {
          blocked.add(f);
        } else if (f.isRequester(uid) && f.responderName == null) {
          // Pedido recusado: o remetente continua vendo "enviado".
          outgoing.add(f);
        }
    }
  }
  int byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  friends.sort((a, b) => byName(a.name, b.name));
  incoming.sort((a, b) => byName(a.requesterName, b.requesterName));
  return FriendshipsView(
    friends: friends,
    incoming: incoming,
    outgoing: outgoing,
    blockedByMe: blocked,
  );
}
