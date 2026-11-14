import 'package:astrum/core/firebase/firestore_paths.dart';
import 'package:astrum/features/profile/domain/public_profile.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/intention_notice.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Future<void> sendIntention({
    required String fromUid,
    required String fromName,
    required String toUid,
    required String intentionId,
    required String intentionLabel,
  }) {
    return _userDoc(toUid).collection('notifications').add({
      'type': 'intention',
      'intentionId': intentionId,
      'intentionLabel': intentionLabel,
      'fromName': fromName,
      'fromUid': fromUid,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

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
