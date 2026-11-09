import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/astrology.dart';
import '../models/app_user.dart';
import 'economy.dart';
import 'public_profile.dart';

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
    await _writePublicProfile(user.uid,
        name: name, avatar: pfp, email: user.email ?? '');
  }

  DocumentReference<Map<String, dynamic>> _publicDoc(String uid) =>
      _db.collection('publicProfiles').doc(uid);

  Future<void> _writePublicProfile(
    String uid, {
    required String name,
    required String? avatar,
    required String email,
  }) async {
    final data = buildPublicProfile(name: name, avatar: avatar, email: email);
    if (data == null) return;
    await _publicDoc(uid).set(data);
  }

  /// Regrava publicProfiles/{uid} a partir do perfil atual em users/{uid}.
  Future<void> syncPublicProfile(String uid) async {
    final data = (await _userDoc(uid).get()).data();
    if (data == null) return;
    final equipped = data['equipped'] as Map<String, dynamic>?;
    final pfp = equipped?['profilePicture'] as String? ??
        defaultProfilePictureId(data['zodiacSign'] as String?);
    await _writePublicProfile(
      uid,
      name: data['name'] as String? ?? '',
      avatar: pfp,
      email: data['email'] as String? ?? _auth.currentUser?.email ?? '',
    );
  }

  static bool _touchesPublicProfile(Iterable<String> keys) => keys.any((k) =>
      k == 'name' ||
      k == 'email' ||
      k == 'equipped' ||
      k == 'equipped.profilePicture');

  Future<void> updateFields(String uid, Map<String, dynamic> data) async {
    await _userDoc(uid).update(data);
    if (_touchesPublicProfile(data.keys)) await syncPublicProfile(uid);
  }

  Stream<Map<String, CatalogEntry>> watchShopCatalog() {
    return _db.collection('shop_items').snapshots().map((snap) => {
          for (final d in snap.docs) d.id: CatalogEntry.fromMap(d.data()),
        });
  }

  /// Compra atomica: le o perfil e o preco do catalogo (shop_items) dentro da
  /// transacao, valida e grava saldo e inventario completo (a regra exige o
  /// inventario antigo + 1 item, e o item novo no fim da lista).
  /// Se [equipField] for informado, equipa o item na mesma gravacao.
  /// Lanca [EconomyException] sem gravar nada quando a compra nao e valida.
  Future<void> purchaseItem({
    required String uid,
    required String itemId,
    String? equipField,
  }) {
    final ref = _userDoc(uid);
    final itemRef = _db.collection('shop_items').doc(itemId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final itemSnap = await tx.get(itemRef);
      final data = snap.data();
      if (data == null) throw StateError('Perfil não encontrado.');
      final itemData = itemSnap.data();
      if (itemData == null) throw const NotPurchasableException();
      final price = resolvePrice(
          {itemId: CatalogEntry.fromMap(itemData)}, itemId);
      final result = computePurchase(
        stardust: ((data['wallet'] as Map?)?['stardust'] as num?)?.toInt() ?? 0,
        inventory: ((data['inventory'] as List?) ?? const []).cast<String>(),
        itemId: itemId,
        price: price,
      );
      tx.update(ref, {
        'wallet.stardust': result.stardust,
        'inventory': result.inventory,
        if (equipField != null) equipField: itemId,
      });
    }).then((_) async {
      if (equipField != null && _touchesPublicProfile([equipField])) {
        await syncPublicProfile(uid);
      }
    });
  }

  /// Check-in diario atomico. [today] no formato `yyyy-MM-dd` (data local; as
  /// regras aceitam UTC +-1 dia). Lanca [AlreadyCheckedInException] se ja feito.
  Future<void> dailyCheckIn({required String uid, required String today}) {
    final ref = _userDoc(uid);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) throw StateError('Perfil não encontrado.');
      final newStardust = computeCheckIn(
        stardust: ((data['wallet'] as Map?)?['stardust'] as num?)?.toInt() ?? 0,
        lastCheckIn: data['dailyCheckIn'] as String?,
        today: today,
      );
      tx.update(ref, {
        'wallet.stardust': newStardust,
        'dailyCheckIn': today,
      });
    });
  }

  Stream<List<RitualEvent>> watchEvents(String uid) {
    return _userDoc(uid)
        .collection('events')
        .orderBy('date')
        .orderBy('time')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => RitualEvent.fromDoc(d.id, d.data())).toList());
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

  /// Busca por e-mail em publicProfiles (hash); nunca le `users`. O Friend
  /// devolvido nao tem e-mail nem signo (nao constam no perfil publico).
  Future<Friend?> findUserByEmail(String email) async {
    if (email.trim().isEmpty) return null;
    final snap = await _db
        .collection('publicProfiles')
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

  /// Migracao: grava publicProfiles para todos os users (so admin le users).
  /// Devolve quantos perfis foram gravados.
  Future<int> rebuildPublicProfiles() async {
    final snap = await _db.collection('users').get();
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
      await _publicDoc(d.id).set(profile);
      count++;
    }
    return count;
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
