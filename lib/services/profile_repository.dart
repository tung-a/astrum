import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/firebase/firestore_paths.dart';
import '../data/astrology.dart';
import '../models/app_user.dart';
import '../models/equip_slot.dart';
import 'equip_slot_field.dart';
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

  Future<void> setNotificationsEnabled(String uid, bool enabled) =>
      _update(uid, {'preferences.notifications': enabled});

  Future<void> setShowSign(String uid, bool enabled) =>
      _update(uid, {'preferences.showSign': enabled});

  /// Equipa [itemId] no [slot]; so o avatar sincroniza publicProfiles.
  /// Se o sync falhar apos o update, o equipado ja esta gravado em users/{uid}
  /// e o erro sobe ao chamador (comportamento preservado; ver opcao B no plano).
  Future<void> equip(String uid, EquipSlot slot, String itemId) async {
    await _update(uid, {slot.fieldPath: itemId});
    if (slot.touchesPublicProfile) await _sync.syncFromUser(uid);
  }

  /// Grava o mapa astral e o signo solar (primeira posicao) na mesma escrita.
  Future<void> saveAstralMap(String uid, List<PlanetPosition> chart) async {
    await _update(uid, {
      'astralMapJson': AppUser.encodeAstralMap(chart),
      'zodiacSign': chart.first.sign,
    });
  }

  Future<void> saveDailyHoroscope(String uid,
          {required String date, required String content}) =>
      _update(uid, {
        'dailyHoroscope': {'date': date, 'content': content},
      });

  Future<void> saveDailyTarot(String uid,
          {required String date,
          required String card,
          required String meaning}) =>
      _update(uid, {
        'dailyTarot': {'date': date, 'card': card, 'meaning': meaning},
      });

  // Unico ponto de escrita do perfil; privado, nenhum metodo publico aceita
  // Map ou caminho de campo (wallet/inventory/role/dailyCheckIn inalcancaveis).
  Future<void> _update(String uid, Map<String, dynamic> data) =>
      _userDoc(uid).update(data);
}
