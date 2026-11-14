import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:astrum/core/firebase/firestore_paths.dart';
import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/data/profile_pictures.dart';
import 'package:astrum/models/shop_item.dart';
import 'package:astrum/features/admin/data/crystal_seed.dart';
import 'package:astrum/models/app_user.dart';
import 'package:astrum/services/public_profile.dart';

/// Falha de uma operacao de admin (mensagem original do Firebase).
class AdminOperationException implements Exception {
  const AdminOperationException(this.message);
  final String message;

  @override
  String toString() => 'AdminOperationException: $message';
}

typedef AnalyticsEventRow = ({String? userId, String? eventName});

/// Valor nao-string (dado malformado) vira null em vez de estourar o cast.
String? _asString(Object? v) => v is String ? v : null;

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.total,
    required this.uniqueUsers,
    required this.counts,
  });
  final int total;
  final int uniqueUsers;
  final Map<String, int> counts;
}

/// Resume os eventos: exclui 'anonymous' dos usuarios unicos e ignora
/// eventName vazio na contagem por nome.
AnalyticsSummary summarizeAnalytics(List<AnalyticsEventRow> rows) {
  final users = <String>{};
  final counts = <String, int>{};
  for (final r in rows) {
    final uid = r.userId;
    if (uid != null && uid != anonymousUserId) users.add(uid);
    final name = r.eventName;
    if (name != null && name.isNotEmpty) {
      counts.update(name, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return AnalyticsSummary(
      total: rows.length, uniqueUsers: users.length, counts: counts);
}

/// Plano puro da publicacao do catalogo (id -> dados para set com merge).
/// Novo: type, rarity, price e active:true. Existente: so type e rarity (o
/// merge preserva price/active). Existente fora do seed: so active:false.
/// Nunca apaga.
Map<String, Map<String, dynamic>> planCatalogPublish({
  required Set<String> existingIds,
  required List<ShopItem> seed,
}) {
  final plan = <String, Map<String, dynamic>>{};
  for (final item in seed) {
    final data = <String, dynamic>{
      'type': catalogTypeName(item.type),
      'rarity': catalogRarityName(item.rarity),
    };
    if (!existingIds.contains(item.id)) {
      data['price'] = item.price;
      data['active'] = true;
    }
    plan[item.id] = data;
  }
  final seedIds = seed.map((i) => i.id).toSet();
  for (final id in existingIds.difference(seedIds)) {
    plan[id] = {'active': false};
  }
  return plan;
}

/// Operacoes restritas a admin.
class AdminRepository {
  AdminRepository(this._db);

  final FirebaseFirestore _db;

  /// Migracao: grava publicProfiles para todos os users (so admin le users).
  /// Devolve quantos perfis foram gravados.
  /// Atencao: firestore.rules so deixa o dono escrever publicProfiles/{uid};
  /// para terceiros a gravacao falha com permission-denied (backlog M1).
  Future<int> rebuildPublicProfiles() async {
    try {
      return await _rebuildPublicProfiles();
    } on FirebaseException catch (e) {
      throw AdminOperationException(e.message ?? '');
    }
  }

  Future<int> _rebuildPublicProfiles() async {
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

  /// Eventos desde [since], mais recentes primeiro, no maximo 500. Range e
  /// orderBy no mesmo campo: sem indice composto novo. Erros propagam crus.
  Stream<List<AnalyticsEventRow>> watchAnalyticsEvents(
      {required DateTime since}) {
    return _db
        .collection('analytics_events')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .limit(500)
        .snapshots()
        .map((snap) => [
              for (final d in snap.docs)
                (
                  userId: _asString(d.data()['userId']),
                  eventName: _asString(d.data()['eventName']),
                ),
            ]);
  }

  Future<void> seedCrystals(
      [List<CrystalSeed> crystals = initialCrystals]) async {
    final batch = _db.batch();
    for (final c in crystals) {
      batch.set(_db.collection('cristais_propriedades').doc(c.id), {
        'nome': c.name,
        'descricao': c.description,
        'foco': c.focus,
      });
    }
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      throw AdminOperationException(e.message ?? '');
    }
  }

  /// Le shop_items (se falhar nada e gravado), aplica [planCatalogPublish] e
  /// grava em um batch com merge. Limite do batch: 500 operacoes; o catalogo
  /// tem dezenas de itens.
  Future<void> publishCatalog(List<ShopItem> seed) async {
    try {
      final existing = await _db.collection('shop_items').get();
      final plan = planCatalogPublish(
        existingIds: existing.docs.map((d) => d.id).toSet(),
        seed: seed,
      );
      final batch = _db.batch();
      plan.forEach((id, data) {
        batch.set(_db.shopItemDoc(id), data, SetOptions(merge: true));
      });
      await batch.commit();
    } on FirebaseException catch (e) {
      throw AdminOperationException(e.message ?? '');
    }
  }
}
