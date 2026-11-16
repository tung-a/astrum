import 'package:astrum/core/firebase/firestore_paths.dart';
import 'package:astrum/core/firebase/paged_delete.dart';
import 'package:astrum/features/profile/domain/public_profile.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/domain/intention_notice.dart';
import 'package:astrum/features/social/domain/recipient_unavailable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Amigos, busca por e-mail e intencoes/notificacoes.
class SocialRepository {
  SocialRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.userDoc(uid);

  Stream<List<Friend>> watchFriends(String uid) {
    return _userDoc(uid).collection('friends').snapshots().map(
          (snap) => snap.docs
              .map(
                (d) => Friend(
                  id: d.id,
                  name: d.data()['name'] as String? ?? 'Viajante',
                  email: d.data()['email'] as String? ?? '',
                  zodiacSign: d.data()['zodiacSign'] as String? ?? '',
                ),
              )
              .toList(),
        );
  }

  // ---- amizades com aceite (friendships/{pairId}, etapa 12)

  /// Todas as relacoes em que [uid] e membro (amigos, pedidos e lapides).
  /// Consulta `array-contains` em campo unico: indice automatico.
  Stream<List<Friendship>> watchFriendships(String uid) {
    return _db.friendshipsCol
        .where('uids', arrayContains: uid)
        .snapshots()
        .map((snap) => [
              for (final d in snap.docs)
                if (Friendship.fromData(d.id, d.data()) case final f?) f,
            ]);
  }

  /// Nome publico de [uid] (publicProfiles), ou null se nao existir/estiver
  /// oculto. So para rotular um pedido enviado, cujo documento ainda nao tem o
  /// nome do destinatario.
  Future<String?> publicNameOf(String uid) async {
    try {
      final snap = await _db.publicDoc(uid).get();
      final name = snap.data()?['name'];
      return name is String && name.isNotEmpty ? name : null;
    } on FirebaseException {
      return null;
    }
  }

  /// Pede amizade a [other]. Transacao: o par tem um unico documento, entao
  /// duplicata e pedido cruzado se resolvem pelo proprio id.
  Future<RequestOutcome> requestFriendship({
    required String me,
    required String myName,
    required String other,
  }) async {
    final ref = _db.friendshipDoc(pairIdOf(me, other));
    try {
      return await runGuarded(() => _db.runTransaction((tx) async {
            final snap = await tx.get(ref);
            if (!snap.exists) {
              tx.set(ref, {
                'uids': [me, other]..sort(),
                'requesterUid': me,
                'requesterName': myName,
                'status': FriendshipStatus.pending.wire,
                'createdAt': FieldValue.serverTimestamp(),
              });
              return RequestOutcome.sent;
            }
            final f = Friendship.fromData(snap.id, snap.data()!);
            if (f == null) return RequestOutcome.unavailable;
            switch (f.status) {
              case FriendshipStatus.accepted:
                return RequestOutcome.alreadyFriends;
              case FriendshipStatus.pending:
                if (f.requesterUid == me) return RequestOutcome.alreadySent;
                // O outro ja tinha pedido: os dois querem, vira amizade.
                tx.update(ref, {
                  'status': FriendshipStatus.accepted.wire,
                  'responderName': myName,
                  'respondedAt': FieldValue.serverTimestamp(),
                });
                return RequestOutcome.crossAccepted;
              case FriendshipStatus.declined:
                // Meu pedido recusado segue como "enviado" (recusa silenciosa).
                if (f.requesterUid == me &&
                    f.declinedBy == other &&
                    f.responderName == null) {
                  return RequestOutcome.alreadySent;
                }
                return RequestOutcome.unavailable;
            }
          }));
    } on FirebaseException catch (e) {
      // Regras negaram o create/aceite: destino sem busca, conta excluida...
      if (e.code == 'permission-denied') return RequestOutcome.unavailable;
      rethrow;
    }
  }

  /// Aceita o pedido de [other]. Idempotente (aceite duplo = sucesso).
  Future<ActionOutcome> acceptFriendship({
    required String me,
    required String myName,
    required String other,
  }) =>
      _act(
        pairIdOf(me, other),
        (ref) => ref.update({
          'status': FriendshipStatus.accepted.wire,
          'responderName': myName,
          'respondedAt': FieldValue.serverTimestamp(),
        }),
        alreadyDone: (f) => f?.status == FriendshipStatus.accepted,
      );

  /// Recusa o pedido de [other] (vira lapide: ele nao pede de novo).
  Future<ActionOutcome> declineFriendship(
          {required String me, required String other}) =>
      _declineLike(me, other);

  /// Remove uma amizade aceita (vira lapide de quem removeu).
  Future<ActionOutcome> removeFriendship(
          {required String me, required String other}) =>
      _declineLike(me, other);

  Future<ActionOutcome> _declineLike(String me, String other) => _act(
        pairIdOf(me, other),
        (ref) => ref.update({
          'status': FriendshipStatus.declined.wire,
          'declinedBy': me,
          'respondedAt': FieldValue.serverTimestamp(),
        }),
        alreadyDone: (f) =>
            f?.status == FriendshipStatus.declined && f?.declinedBy == me,
      );

  /// Cancela um pedido meu ainda pendente.
  Future<ActionOutcome> cancelRequest(
          {required String me, required String other}) =>
      _act(
        pairIdOf(me, other),
        (ref) => ref.delete(),
        alreadyDone: (f) => f == null,
      );

  /// Desbloqueia: apaga a lapide que EU criei (recusa ou remocao).
  Future<ActionOutcome> unblock({required String me, required String other}) =>
      _act(
        pairIdOf(me, other),
        (ref) => ref.delete(),
        alreadyDone: (f) => f == null,
      );

  /// Executa [op]; se as regras negarem ou o documento sumir, relê o par e
  /// decide entre "ja estava feito" e "nao existe mais". Outros erros
  /// (`unavailable`, etc.) sobem.
  Future<ActionOutcome> _act(
    String pairId,
    Future<void> Function(DocumentReference<Map<String, dynamic>> ref) op, {
    required bool Function(Friendship? current) alreadyDone,
  }) async {
    final ref = _db.friendshipDoc(pairId);
    try {
      await runGuarded(() => op(ref));
      return ActionOutcome.done;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' && e.code != 'not-found') rethrow;
      final DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await ref.get();
      } on FirebaseException {
        rethrow; // sem a releitura nao da para decidir: erro original
      }
      final current =
          snap.exists ? Friendship.fromData(snap.id, snap.data()!) : null;
      return alreadyDone(current) ? ActionOutcome.done : ActionOutcome.gone;
    }
  }

  /// Busca por e-mail em publicProfiles (hash); nunca le `users`. O Friend
  /// devolvido nao tem e-mail nem signo (nao constam no perfil publico).
  Future<Friend?> findUserByEmail(String email) async {
    if (email.trim().isEmpty) return null;
    final snap = await _db.publicCol
        .where('emailHash', isEqualTo: hashEmail(email))
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return Friend(
      id: d.id,
      name: d.data()['name'] as String? ?? 'Viajante',
      avatar: d.data()['avatar'] as String? ?? '',
    );
  }

  Future<void> addFriend(String uid, Friend friend) {
    return _userDoc(uid).collection('friends').doc(friend.id).set({
      'name': friend.name,
      'email': friend.email,
      'zodiacSign': friend.zodiacSign,
    });
  }

  /// Envia a intencao. Se as regras negarem (`permission-denied`) e o perfil
  /// publico do destino tambem nao existir, a conta foi excluida: lanca
  /// [RecipientUnavailableException]. Outros erros sobem como estao.
  Future<void> sendIntention({
    required String fromUid,
    required String fromName,
    required String toUid,
    required String intentionId,
    required String intentionLabel,
  }) async {
    try {
      await writeNotification(toUid, {
        'type': 'intention',
        'intentionId': intentionId,
        'intentionLabel': intentionLabel,
        'fromName': fromName,
        'fromUid': fromUid,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      var gone = false;
      try {
        gone = !(await _db.publicDoc(toUid).get()).exists;
      } catch (_) {
        gone = false;
      }
      if (gone) throw const RecipientUnavailableException();
      rethrow;
    }
  }

  /// Executa uma escrita das amizades. So sobrescrevivel em teste (injetar
  /// `permission-denied`, `unavailable`...: fake_cloud_firestore nao avalia
  /// regras).
  @visibleForTesting
  Future<T> runGuarded<T>(Future<T> Function() op) => op();

  /// Grava a notificacao na caixa do destino. So sobrescrevivel em teste.
  @visibleForTesting
  Future<void> writeNotification(String toUid, Map<String, dynamic> data) =>
      _userDoc(toUid).collection('notifications').add(data);

  /// Remove um amigo da PROPRIA lista (limpeza de conta excluida).
  Future<void> removeFriend(String uid, String friendId) =>
      _userDoc(uid).collection('friends').doc(friendId).delete();

  // ---- exclusao de conta (cada metodo e idempotente; offline lanca
  // ServerOfflineException)

  Future<void> deleteAllFriends(String uid) =>
      deleteQueryPaged(_userDoc(uid).collection('friends'));

  /// Apaga todas as relacoes do uid (amigos, pedidos enviados/recebidos e
  /// lapides). Roda DEPOIS de apagar o perfil: o marcador "perfil ausente" e o
  /// que as regras exigem para apagar relacoes alheias a mim (recusado etc.).
  Future<void> deleteAllFriendships(String uid) =>
      deleteQueryPaged(_db.friendshipsCol.where('uids', arrayContains: uid));

  /// Notificacoes que o usuario RECEBEU (na propria caixa).
  Future<void> deleteAllReceivedNotifications(String uid) =>
      deleteQueryPaged(_userDoc(uid).collection('notifications'));

  /// Intencoes que o usuario ENVIOU, em qualquer caixa (collection group por
  /// `fromUid`; exige o indice e as regras da etapa 11).
  Future<void> deleteSentIntentions(String uid) => deleteQueryPaged(
      _db.collectionGroup('notifications').where('fromUid', isEqualTo: uid));

  Stream<IntentionNotice?> watchUnreadIntention(String uid) {
    return _userDoc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      final d = snap.docs.first;
      return IntentionNotice(
        id: d.id,
        intentionId: d.data()['intentionId'] as String? ?? '',
        intentionLabel: d.data()['intentionLabel'] as String? ?? '',
        fromName: d.data()['fromName'] as String? ?? 'Alguém',
      );
    });
  }

  Future<void> markNotificationRead(String uid, String id) {
    return _userDoc(uid)
        .collection('notifications')
        .doc(id)
        .update({'read': true});
  }
}
