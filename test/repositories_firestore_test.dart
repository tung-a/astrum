import 'package:astrum/core/astro/natal_chart.dart';
import 'package:astrum/models/app_user.dart';
import 'package:astrum/models/ritual_event.dart';
import 'package:astrum/models/friend.dart';
import 'package:astrum/models/equip_slot.dart';
import 'package:astrum/services/admin_repository.dart';
import 'package:astrum/services/events_repository.dart';
import 'package:astrum/services/profile_repository.dart';
import 'package:astrum/services/public_profile.dart';
import 'package:astrum/services/public_profile_sync.dart';
import 'package:astrum/services/social_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

/// Sync que falha ao regravar publicProfiles (lacuna B1 da etapa 5).
class _SyncFalhando extends PublicProfileSync {
  _SyncFalhando(FirebaseFirestore db) : super(db: db, auth: FakeFirebaseAuth());

  @override
  Future<void> syncFromUser(String uid) async =>
      throw StateError('falha simulada no publicProfiles');
}

void main() {
  createProfileTests();
  group('AdminRepository.rebuildPublicProfiles', () {
    // Obs.: o fake_cloud_firestore NAO aplica firestore.rules. Nas regras
    // atuais so o dono escreve publicProfiles/{uid}; um admin gravando o de
    // terceiros recebe permission-denied em producao (backlog M1).
    test('conta so os perfis gravados e pula os que nao geram perfil',
        () async {
      final db = FakeFirebaseFirestore();
      await db
          .collection('users')
          .doc('a')
          .set({'name': 'Ana', 'email': 'ana@x.com', 'zodiacSign': 'Aries'});
      await db
          .collection('users')
          .doc('b')
          .set({'name': 'Bia', 'email': 'bia@x.com'});
      // sem e-mail: buildPublicProfile devolve null.
      await db.collection('users').doc('c').set({'name': 'Cris'});

      final n = await AdminRepository(db).rebuildPublicProfiles();

      expect(n, 2);
      final pub = await db.collection('publicProfiles').get();
      expect(pub.docs.map((d) => d.id).toSet(), {'a', 'b'});
      expect(
          (await db.collection('publicProfiles').doc('a').get())
              .data()!['emailHash'],
          hashEmail('ana@x.com'));
    });
  });

  group('SocialRepository', () {
    test('findUserByEmail usa publicProfiles', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('publicProfiles').doc('u1').set(
          {'name': 'Ana', 'avatar': 'pfp', 'emailHash': hashEmail('a@x.com')});
      final repo = SocialRepository(db);
      final f = await repo.findUserByEmail('a@x.com');
      expect(f?.id, 'u1');
      expect(f?.avatar, 'pfp');
      expect(await repo.findUserByEmail('x@x.com'), isNull);
      expect(await repo.findUserByEmail('  '), isNull);
    });

    test('addFriend e watchFriends', () async {
      final repo = SocialRepository(FakeFirebaseFirestore());
      await repo.addFriend(
          'me', const Friend(id: 'f1', name: 'Fê', email: 'f@x.com'));
      final list = await repo.watchFriends('me').first;
      expect(list.single.id, 'f1');
      expect(list.single.name, 'Fê');
    });

    test('sendIntention, watchUnreadIntention e markNotificationRead',
        () async {
      final repo = SocialRepository(FakeFirebaseFirestore());
      await repo.sendIntention(
        fromUid: 'a',
        fromName: 'Ana',
        toUid: 'b',
        intentionId: 'i1',
        intentionLabel: 'Paz',
      );
      final notice = await repo.watchUnreadIntention('b').first;
      expect(notice?.fromName, 'Ana');
      expect(notice?.intentionLabel, 'Paz');
      await repo.markNotificationRead('b', notice!.id);
      expect(await repo.watchUnreadIntention('b').first, isNull);
    });
  });

  group('EventsRepository', () {
    test('add, watch (ordenado) e delete', () async {
      final repo = EventsRepository(FakeFirebaseFirestore());
      const base =
          RitualEvent(id: '', title: 'B', time: '10:00', date: '2026-01-02');
      await repo.addEvent('u', base);
      await repo.addEvent(
          'u',
          const RitualEvent(
              id: '', title: 'A', time: '09:00', date: '2026-01-01'));
      final list = await repo.watchEvents('u').first;
      expect(list.map((e) => e.title), ['A', 'B']);
      await repo.deleteEvent('u', list.first.id);
      final after = await repo.watchEvents('u').first;
      expect(after.map((e) => e.title), ['B']);
    });
  });

  group('ProfileRepository (escritas tipadas)', () {
    late FakeFirebaseFirestore db;
    late ProfileRepository repo;

    Future<Map<String, dynamic>> user() async =>
        (await db.collection('users').doc('u').get()).data()!;
    Future<DocumentSnapshot<Map<String, dynamic>>> pub() =>
        db.collection('publicProfiles').doc('u').get();

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = ProfileRepository(
        db: db,
        sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth()),
      );
      await db.collection('users').doc('u').set({
        'name': 'Ana',
        'email': 'ana@x.com',
        'role': 'user',
        'zodiacSign': 'Aries',
        'equipped': {
          'skin': 'skin_classic',
          'background': 'bg_void',
          'profilePicture': 'pfp1',
        },
        'wallet': {'stardust': 5},
        'inventory': ['skin_classic', 'bg_void'],
        'dailyCheckIn': '2026-01-01',
        'preferences': {
          'notifications': true,
          'publicProfile': true,
          'showSign': true,
        },
      });
    });

    test('equip(profilePicture) grava a chave e sincroniza publicProfiles',
        () async {
      await repo.equip('u', EquipSlot.profilePicture, 'pfp2');
      expect((await user())['equipped'], {
        'skin': 'skin_classic',
        'background': 'bg_void',
        'profilePicture': 'pfp2',
      });
      final p = (await pub()).data()!;
      expect(p['avatar'], 'pfp2');
      expect(p['name'], 'Ana');
      expect(p['emailHash'], hashEmail('ana@x.com'));
    });

    test('equip(skin) e equip(background) gravam sem sincronizar', () async {
      await repo.equip('u', EquipSlot.skin, 'skin_x');
      await repo.equip('u', EquipSlot.background, 'bg_x');
      final e = (await user())['equipped'] as Map;
      expect(e['skin'], 'skin_x');
      expect(e['background'], 'bg_x');
      expect(e['profilePicture'], 'pfp1');
      expect((await pub()).exists, isFalse);
    });

    test(
        'setNotificationsEnabled e setShowSign gravam so a sua chave, sem sync',
        () async {
      await repo.setNotificationsEnabled('u', false);
      await repo.setShowSign('u', false);
      expect((await user())['preferences'], {
        'notifications': false,
        'publicProfile': true,
        'showSign': false,
      });
      expect((await pub()).exists, isFalse);
    });

    test('saveAstralMap grava astralMapJson e zodiacSign sem sync', () async {
      const chart = [
        PlanetPosition(
            planet: 'Sol',
            sign: 'Leao',
            house: '1',
            element: 'Fogo',
            summary: 's'),
      ];
      await repo.saveAstralMap('u', chart);
      final d = await user();
      expect(d['zodiacSign'], 'Leao');
      expect(d['astralMapJson'], AppUser.encodeAstralMap(chart));
      expect((await pub()).exists, isFalse);
    });

    test('saveAstralMap com lista vazia lanca StateError sem gravar', () async {
      await expectLater(repo.saveAstralMap('u', const []), throwsStateError);
      expect((await user())['zodiacSign'], 'Aries');
    });

    test('saveDailyHoroscope e saveDailyTarot gravam as chaves esperadas',
        () async {
      await repo.saveDailyHoroscope('u', date: '2026-02-01', content: 'texto');
      await repo.saveDailyTarot('u',
          date: '2026-02-01', card: 'O Louco', meaning: 'inicio');
      final d = await user();
      expect(d['dailyHoroscope'], {'date': '2026-02-01', 'content': 'texto'});
      expect(d['dailyTarot'],
          {'date': '2026-02-01', 'card': 'O Louco', 'meaning': 'inicio'});
      expect((await pub()).exists, isFalse);
    });

    test(
        'M1 (caracterizacao): saveAstralMap troca zodiacSign mas nao regrava '
        'publicProfiles existente (avatar publico defasado)', () async {
      await db.collection('publicProfiles').doc('u').set({
        'name': 'Ana',
        'avatar': 'pfp1',
        'emailHash': hashEmail('ana@x.com'),
      });
      await repo.saveAstralMap('u', const [
        PlanetPosition(
            planet: 'Sol',
            sign: 'Leao',
            house: '1',
            element: 'Fogo',
            summary: 's'),
      ]);
      expect((await user())['zodiacSign'], 'Leao');
      expect((await pub()).data()!['avatar'], 'pfp1');
    });

    test(
        'B1 (caracterizacao): equip(profilePicture) com falha do sync propaga '
        'erro, mas equipped ja esta gravado em users', () async {
      final falhando = ProfileRepository(
        db: db,
        sync: _SyncFalhando(db),
      );

      await expectLater(
        falhando.equip('u', EquipSlot.profilePicture, 'pfp2'),
        throwsStateError,
      );
      expect(((await user())['equipped'] as Map)['profilePicture'], 'pfp2');
      expect((await pub()).exists, isFalse);
    });

    test('nenhum metodo tipado altera wallet/inventory/role/dailyCheckIn',
        () async {
      final before = await user();
      await repo.setNotificationsEnabled('u', false);
      await repo.setShowSign('u', false);
      for (final s in EquipSlot.values) {
        await repo.equip('u', s, 'item_${s.name}');
      }
      await repo.saveAstralMap('u', const [
        PlanetPosition(
            planet: 'Sol',
            sign: 'Leao',
            house: '1',
            element: 'Fogo',
            summary: 's'),
      ]);
      await repo.saveDailyHoroscope('u', date: 'd', content: 'c');
      await repo.saveDailyTarot('u', date: 'd', card: 'c', meaning: 'm');
      final after = await user();
      for (final k in ['wallet', 'inventory', 'role', 'dailyCheckIn']) {
        expect(after[k], before[k], reason: k);
      }
      expect(after['name'], before['name']);
      expect(after['email'], before['email']);
    });
  });
}

/// Db que delega ao fake mas cujo batch falha no commit (sem escrita parcial).
class _DbCommitFalha implements FirebaseFirestore {
  _DbCommitFalha(this.inner);
  final FakeFirebaseFirestore inner;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      inner.collection(path);

  @override
  WriteBatch batch() => _BatchFalha();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _BatchFalha implements WriteBatch {
  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {}

  @override
  Future<void> commit() async => throw StateError('commit falhou');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void createProfileTests() {
  group('ProfileRepository.createProfile (batch)', () {
    Future<void> create(ProfileRepository repo, {String name = 'Nova'}) =>
        repo.createProfile(
          user: FakeUser('nova', email: 'nova@example.com'),
          name: name,
          birthDate: '01/01/2000',
          birthTime: '10:00',
          birthPlace: 'SP',
          zodiacSign: 'Aries',
        );

    test('grava users e publicProfiles com os campos esperados', () async {
      final db = FakeFirebaseFirestore();
      final repo = ProfileRepository(
          db: db, sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth()));
      await create(repo);
      final u = (await db.collection('users').doc('nova').get()).data()!;
      expect(u['wallet'], {'stardust': 500});
      expect(u['role'], 'user');
      expect(u['email'], 'nova@example.com');
      expect(u['birthPlace'], 'SP');
      final pub =
          (await db.collection('publicProfiles').doc('nova').get()).data()!;
      expect(pub.keys.toSet(), {'name', 'avatar', 'emailHash'});
    });

    test('nome invalido nao grava publicProfiles', () async {
      final db = FakeFirebaseFirestore();
      final repo = ProfileRepository(
          db: db, sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth()));
      await create(repo, name: '   ');
      expect((await db.collection('users').doc('nova').get()).exists, isTrue);
      expect((await db.collection('publicProfiles').doc('nova').get()).exists,
          isFalse);
    });

    test('commit que falha nao deixa escrita parcial', () async {
      final inner = FakeFirebaseFirestore();
      final repo = ProfileRepository(
          db: _DbCommitFalha(inner),
          sync: PublicProfileSync(db: inner, auth: FakeFirebaseAuth()));
      await expectLater(create(repo), throwsStateError);
      expect(
          (await inner.collection('users').doc('nova').get()).exists, isFalse);
      expect(
          (await inner.collection('publicProfiles').doc('nova').get()).exists,
          isFalse);
    });
  });
}
