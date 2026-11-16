import 'dart:async';

import 'package:astrum/core/astro/natal_chart.dart';
import 'package:astrum/core/firebase/firestore_paths.dart';
import 'package:astrum/core/firebase/paged_delete.dart';
import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/features/economy/domain/equip_slot.dart';
import 'package:astrum/features/economy/domain/equip_slot_field.dart';
import 'package:astrum/features/economy/domain/profile_pictures.dart';
import 'package:astrum/features/profile/data/public_profile_sync.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/domain/public_profile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Perfil do usuario logado. Nenhum metodo publico aceita Map ou caminho de
/// campo (wallet/inventory/role/dailyCheckIn inalcancaveis).
abstract interface class ProfileRepository {
  /// Perfil do [user]; quem escolhe o usuario e o profileProvider. Emite
  /// `null` quando `users/{uid}` NAO existe no servidor ("perfil ausente":
  /// conta sem perfil ou exclusao em andamento). Snapshot inexistente que
  /// veio so do cache (offline) nao conclui nada e nao emite.
  Stream<AppUser?> watchProfile(User user);

  Future<void> createProfile({
    required User user,
    required String name,
    required String birthDate,
    required String birthTime,
    required String birthPlace,
    required String zodiacSign,
  });

  Future<void> setNotificationsEnabled(String uid, bool enabled);

  Future<void> setShowSign(String uid, bool enabled);

  /// Equipa [itemId] no [slot]; so o avatar sincroniza publicProfiles.
  Future<void> equip(String uid, EquipSlot slot, String itemId);

  /// Grava o mapa astral e o signo solar (primeira posicao) na mesma escrita.
  Future<void> saveAstralMap(String uid, List<PlanetPosition> chart);

  Future<void> saveDailyHoroscope(String uid,
      {required String date, required String content});

  Future<void> saveDailyTarot(String uid,
      {required String date, required String card, required String meaning});

  /// Exclusao de conta: apaga `users/{uid}` e `publicProfiles/{uid}` em UM
  /// batch (o documento ausente e o marcador de "exclusao em andamento").
  /// Idempotente. Offline (commit que nao completa) lanca
  /// [ServerOfflineException].
  Future<void> deleteProfile(String uid);
}

class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository({
    required FirebaseFirestore db,
    required PublicProfileSync sync,
    this.commitTimeout = const Duration(seconds: 15),
  })  : _db = db,
        _sync = sync;

  /// Prazo do commit de exclusao (offline ele nunca completa).
  final Duration commitTimeout;

  final FirebaseFirestore _db;
  final PublicProfileSync _sync;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.userDoc(uid);

  /// Perfil do [user] (snapshot de users/{uid}). Quem decide qual usuario
  /// observar e o profileProvider (via authStateProvider), que cancela a
  /// assinatura anterior ao trocar de usuario; o repositorio nao abre
  /// authStateChanges.
  @override
  Stream<AppUser?> watchProfile(User user) {
    final snaps =
        _userDoc(user.uid).snapshots(includeMetadataChanges: true).map((s) => (
              exists: s.exists,
              fromCache: s.metadata.isFromCache,
              data: s.data(),
            ));
    return mapProfileSnapshots(
      snaps,
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? 'Viajante',
    );
  }

  /// Regra de "perfil ausente" sobre snapshots simplificados (testavel sem
  /// Firestore): descarta inexistente vindo so do cache (offline sem cache nao
  /// conclui "ausente"), emite `null` para inexistente do servidor e ignora
  /// mudancas so de metadados (mesmos dados).
  @visibleForTesting
  static Stream<AppUser?> mapProfileSnapshots(
    Stream<({bool exists, bool fromCache, Map<String, dynamic>? data})> snaps, {
    required String uid,
    required String email,
    required String displayName,
  }) {
    // Transformer (e nao async*): cancelar a assinatura nao pode esperar o
    // proximo evento do stream de origem.
    bool? lastExists;
    Map<String, dynamic>? lastData;
    return snaps.transform(StreamTransformer.fromHandlers(
      handleData: (s, sink) {
        if (!s.exists && s.fromCache) return;
        if (lastExists == s.exists && _sameData(lastData, s.data)) return;
        lastExists = s.exists;
        lastData = s.data;
        sink.add(s.exists
            ? AppUser.fromFirebase(
                uid: uid, email: email, displayName: displayName, data: s.data)
            : null);
      },
    ));
  }

  static bool _sameData(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_sameData(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameData(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  @override
  Future<void> createProfile({
    required User user,
    required String name,
    required String birthDate,
    required String birthTime,
    required String birthPlace,
    required String zodiacSign,
  }) async {
    final pfp = defaultProfilePictureId(zodiacSign);
    // Um unico commit: users/{uid} e publicProfiles/{uid} entram juntos ou
    // nenhum entra (o rollback do cadastro nao pode deixar users/ orfao, ja
    // que as regras proibem delete). As regras validam cada doc em separado.
    final batch = _db.batch();
    batch.set(_userDoc(user.uid), {
      'name': name,
      'email': user.email,
      'birthDate': birthDate,
      'birthTime': birthTime,
      'birthPlace': birthPlace,
      'role': roleUser,
      'zodiacSign': zodiacSign,
      'astrologyData': {'sun': zodiacSign, 'moon': null, 'ascendant': null},
      'wallet': {'stardust': initialStardust},
      'inventory': [
        ...defaultInventory,
        if (pfp.isNotEmpty) pfp,
      ],
      'equipped': {
        'skin': defaultSkinId,
        'background': defaultBackgroundId,
        'profilePicture': pfp.isEmpty ? null : pfp,
      },
      'preferences': {
        'notifications': true,
        'publicProfile': true,
        'showSign': true,
      },
    });
    final public =
        buildPublicProfile(name: name, avatar: pfp, email: user.email ?? '');
    if (public != null) batch.set(_db.publicDoc(user.uid), public);
    await batch.commit();
  }

  @override
  Future<void> setNotificationsEnabled(String uid, bool enabled) =>
      _update(uid, {'preferences.notifications': enabled});

  @override
  Future<void> setShowSign(String uid, bool enabled) =>
      _update(uid, {'preferences.showSign': enabled});

  /// Equipa [itemId] no [slot]; so o avatar sincroniza publicProfiles.
  /// Se o sync falhar apos o update, o equipado ja esta gravado em users/{uid}
  /// e o erro sobe ao chamador (comportamento preservado; ver opcao B no plano).
  @override
  Future<void> equip(String uid, EquipSlot slot, String itemId) async {
    await _update(uid, {slot.fieldPath: itemId});
    if (slot.touchesPublicProfile) await _sync.syncFromUser(uid);
  }

  /// Grava o mapa astral e o signo solar (primeira posicao) na mesma escrita.
  @override
  Future<void> saveAstralMap(String uid, List<PlanetPosition> chart) async {
    await _update(uid, {
      'astralMapJson': AppUser.encodeAstralMap(chart),
      'zodiacSign': chart.first.sign,
    });
  }

  @override
  Future<void> saveDailyHoroscope(String uid,
          {required String date, required String content}) =>
      _update(uid, {
        'dailyHoroscope': {'date': date, 'content': content},
      });

  @override
  Future<void> saveDailyTarot(String uid,
          {required String date,
          required String card,
          required String meaning}) =>
      _update(uid, {
        'dailyTarot': {'date': date, 'card': card, 'meaning': meaning},
      });

  /// Commit do batch de exclusao. So sobrescrevivel em teste.
  @visibleForTesting
  Future<void> commitDelete(WriteBatch batch) => batch.commit();

  @override
  Future<void> deleteProfile(String uid) async {
    final batch = _db.batch()
      ..delete(_userDoc(uid))
      ..delete(_db.publicDoc(uid));
    try {
      await commitDelete(batch).timeout(commitTimeout);
    } on TimeoutException {
      throw const ServerOfflineException();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        throw const ServerOfflineException();
      }
      rethrow;
    }
  }

  // Unico ponto de escrita do perfil; privado, nenhum metodo publico aceita
  // Map ou caminho de campo (wallet/inventory/role/dailyCheckIn inalcancaveis).
  Future<void> _update(String uid, Map<String, dynamic> data) =>
      _userDoc(uid).update(data);
}
