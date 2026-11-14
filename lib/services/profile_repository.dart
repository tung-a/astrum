import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/firebase/firestore_paths.dart';
import '../data/astrology.dart';
import '../models/app_user.dart';
import 'public_profile_sync.dart';

/// Perfil do usuario logado.
class ProfileRepository {
  ProfileRepository({
    required FirebaseFirestore db,
    required PublicProfileSync sync,
  })  : _db = db,
        _sync = sync;

  final FirebaseFirestore _db;
  final PublicProfileSync _sync;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.userDoc(uid);

  /// Perfil do [user] (snapshot de users/{uid}). Quem decide qual usuario
  /// observar e o profileProvider (via authStateProvider), que cancela a
  /// assinatura anterior ao trocar de usuario; o repositorio nao abre
  /// authStateChanges.
  Stream<AppUser?> watchProfile(User user) {
    return _userDoc(user.uid).snapshots().map((snap) {
      return AppUser.fromFirebase(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? 'Viajante',
        data: snap.data(),
      );
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
    await _sync.write(user.uid,
        name: name, avatar: pfp, email: user.email ?? '');
  }

  static const _blockedPrefixes = ['wallet', 'inventory', 'dailyCheckIn', 'role'];

  // etapa 5: remover. EconomyRepository e o unico escritor de `wallet.*`
  // (e de inventory/dailyCheckIn); isso e imposto aqui: chaves proibidas
  // lancam ArgumentError antes de qualquer gravacao.
  Future<void> updateFields(String uid, Map<String, dynamic> data) async {
    for (final k in data.keys) {
      if (_blockedPrefixes.any(k.startsWith)) {
        throw ArgumentError.value(
            k, 'data', 'campo protegido; use o repositorio proprio');
      }
    }
    await _userDoc(uid).update(data);
    if (PublicProfileSync.touches(data.keys)) await _sync.syncFromUser(uid);
  }
}
