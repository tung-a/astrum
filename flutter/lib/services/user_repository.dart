import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/astrology.dart';
import '../models/app_user.dart';

class UserRepository {
  UserRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  Stream<AppUser?> watchProfile() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream<AppUser?>.value(null);
      return _userDoc(user.uid).snapshots().map((snap) {
        return AppUser.fromFirebase(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName ?? 'Viajante',
          data: snap.data(),
        );
      });
    });
  }

  Future<void> createProfile({
    required User user,
    required String name,
    required String birthDate,
    required String birthTime,
    required String birthPlace,
    required String zodiacSign,
  }) async {
    final pfp = defaultProfilePictureId(zodiacSign);
    await _userDoc(user.uid).set({
      'name': name,
      'email': user.email,
      'birthDate': birthDate,
      'birthTime': birthTime,
      'birthPlace': birthPlace,
      'role': 'user',
      'zodiacSign': zodiacSign,
      'astrologyData': {'sun': zodiacSign, 'moon': null, 'ascendant': null},
      'wallet': {'stardust': 500},
      'inventory': [
        'skin_classic',
        'bg_void',
        if (pfp.isNotEmpty) pfp,
      ],
      'equipped': {
        'skin': 'skin_classic',
        'background': 'bg_void',
        'profilePicture': pfp.isEmpty ? null : pfp,
      },
      'preferences': {
        'notifications': true,
        'publicProfile': true,
        'showSign': true,
      },
    });
  }

  Future<void> updateFields(String uid, Map<String, dynamic> data) async {
    try {
      await _userDoc(uid).update(data);
    } catch (_) {
      await _userDoc(uid).set(data, SetOptions(merge: true));
    }
  }

  Stream<List<RitualEvent>> watchEvents(String uid) {
    return _userDoc(uid)
        .collection('events')
        .orderBy('date')
        .orderBy('time')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => RitualEvent.fromDoc(d.id, d.data()))
            .toList());
  }

  Future<void> addEvent(String uid, RitualEvent event) {
    return _userDoc(uid).collection('events').add({
      'title': event.title,
      'time': event.time,
      'date': event.date,
      'duration': event.duration,
      'energy': event.energy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteEvent(String uid, String eventId) {
    return _userDoc(uid).collection('events').doc(eventId).delete();
  }

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

  Future<Friend?> findUserByEmail(String email) async {
    final snap = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      final alt = await _db
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      if (alt.docs.isEmpty) return null;
      final d = alt.docs.first;
      return Friend(
        id: d.id,
        name: d.data()['name'] as String? ?? 'Viajante',
        email: d.data()['email'] as String? ?? '',
        zodiacSign: d.data()['zodiacSign'] as String? ?? '',
      );
    }
    final d = snap.docs.first;
    return Friend(
      id: d.id,
      name: d.data()['name'] as String? ?? 'Viajante',
      email: d.data()['email'] as String? ?? '',
      zodiacSign: d.data()['zodiacSign'] as String? ?? '',
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
    return _db.collection('users').doc(toUid).collection('notifications').add({
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

  Future<List<AppUser>> listUsers() async {
    final snap = await _db.collection('users').limit(80).get();
    return snap.docs
        .map(
          (d) => AppUser.fromFirebase(
            uid: d.id,
            email: d.data()['email'] as String? ?? '',
            displayName: d.data()['name'] as String? ?? '',
            data: d.data(),
          ),
        )
        .toList();
  }
}
