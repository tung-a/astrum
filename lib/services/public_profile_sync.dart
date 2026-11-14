import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/firebase/firestore_paths.dart';
import '../data/astrology.dart';
import 'public_profile.dart';

/// Grava publicProfiles/{uid}. Usado por Profile, Economy e Admin.
class PublicProfileSync {
  PublicProfileSync({required FirebaseFirestore db, required FirebaseAuth auth})
      : _db = db,
        _auth = auth;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<void> write(
    String uid, {
    required String name,
    required String? avatar,
    required String email,
  }) async {
    final data = buildPublicProfile(name: name, avatar: avatar, email: email);
    if (data == null) return;
    await _db.publicDoc(uid).set(data);
  }

  /// Regrava publicProfiles/{uid} a partir do perfil atual em users/{uid}.
  Future<void> syncFromUser(String uid) async {
    final data = (await _db.userDoc(uid).get()).data();
    if (data == null) return;
    final equipped = data['equipped'] as Map<String, dynamic>?;
    final pfp = equipped?['profilePicture'] as String? ??
        defaultProfilePictureId(data['zodiacSign'] as String?);
    await write(
      uid,
      name: data['name'] as String? ?? '',
      avatar: pfp,
      email: data['email'] as String? ?? _auth.currentUser?.email ?? '',
    );
  }

  static bool touches(Iterable<String> keys) => keys.any((k) =>
      k == 'name' ||
      k == 'email' ||
      k == 'equipped' ||
      k == 'equipped.profilePicture');
}
