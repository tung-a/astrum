import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_paths.dart';
import '../data/astrology.dart';
import '../models/app_user.dart';
import 'public_profile.dart';

/// Operacoes restritas a admin.
class AdminRepository {
  AdminRepository(this._db);

  final FirebaseFirestore _db;

  /// Migracao: grava publicProfiles para todos os users (so admin le users).
  /// Devolve quantos perfis foram gravados.
  /// Atencao: firestore.rules so deixa o dono escrever publicProfiles/{uid};
  /// para terceiros a gravacao falha com permission-denied (backlog M1).
  Future<int> rebuildPublicProfiles() async {
    final snap = await _db.usersCol.get();
    var count = 0;
    for (final d in snap.docs) {
      final data = d.data();
      final equipped = data['equipped'] as Map<String, dynamic>?;
      final profile = buildPublicProfile(
        name: data['name'] as String? ?? '',
        avatar: equipped?['profilePicture'] as String? ??
            defaultProfilePictureId(data['zodiacSign'] as String?),
        email: data['email'] as String? ?? '',
      );
      if (profile == null) continue;
      await _db.publicDoc(d.id).set(profile);
      count++;
    }
    return count;
  }

  Future<List<AppUser>> listUsers() async {
    final snap = await _db.usersCol.limit(80).get();
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
