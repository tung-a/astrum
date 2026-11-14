import 'package:astrum/models/app_user.dart';
import 'package:astrum/services/admin_repository.dart';
import 'package:astrum/services/events_repository.dart';
import 'package:astrum/services/profile_repository.dart';
import 'package:astrum/services/public_profile.dart';
import 'package:astrum/services/public_profile_sync.dart';
import 'package:astrum/services/social_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

void main() {
  group('AdminRepository.rebuildPublicProfiles', () {
    // Obs.: o fake_cloud_firestore NAO aplica firestore.rules. Nas regras
    // atuais so o dono escreve publicProfiles/{uid}; um admin gravando o de
    // terceiros recebe permission-denied em producao (backlog M1).
    test('conta so os perfis gravados e pula os que nao geram perfil', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('a').set(
          {'name': 'Ana', 'email': 'ana@x.com', 'zodiacSign': 'Aries'});
      await db.collection('users').doc('b').set(
          {'name': 'Bia', 'email': 'bia@x.com'});
      // sem e-mail: buildPublicProfile devolve null.
      await db.collection('users').doc('c').set({'name': 'Cris'});

      final n = await AdminRepository(db).rebuildPublicProfiles();

      expect(n, 2);
      final pub = await db.collection('publicProfiles').get();
      expect(pub.docs.map((d) => d.id).toSet(), {'a', 'b'});
      expect((await db.collection('publicProfiles').doc('a').get())
          .data()!['emailHash'], hashEmail('ana@x.com'));
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
      const base = RitualEvent(
          id: '', title: 'B', time: '10:00', date: '2026-01-02');
      await repo.addEvent('u', base);
      await repo.addEvent('u',
          const RitualEvent(id: '', title: 'A', time: '09:00', date: '2026-01-01'));
      final list = await repo.watchEvents('u').first;
      expect(list.map((e) => e.title), ['A', 'B']);
      await repo.deleteEvent('u', list.first.id);
      final after = await repo.watchEvents('u').first;
      expect(after.map((e) => e.title), ['B']);
    });
  });

  group('ProfileRepository.updateFields', () {
    late FakeFirebaseFirestore db;
    late ProfileRepository repo;

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = ProfileRepository(
        db: db,
        sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth()),
      );
      await db.collection('users').doc('u').set({
        'name': 'Ana',
        'email': 'ana@x.com',
        'zodiacSign': 'Aries',
        'equipped': {'profilePicture': 'pfp1'},
        'wallet': {'stardust': 5},
      });
    });

    test('sincroniza publicProfiles quando toca nome/avatar', () async {
      await repo.updateFields('u', {'name': 'Ana Maria'});
      final pub = await db.collection('publicProfiles').doc('u').get();
      expect(pub.data()!['name'], 'Ana Maria');
      expect(pub.data()!['avatar'], 'pfp1');
    });

    test('nao sincroniza quando nao toca perfil publico', () async {
      await repo.updateFields('u', {'preferences.showSign': false});
      expect((await db.collection('publicProfiles').doc('u').get()).exists,
          isFalse);
    });

    test('rejeita chaves protegidas sem gravar', () async {
      for (final k in [
        'wallet.stardust',
        'wallet',
        'inventory',
        'dailyCheckIn',
        'dailyCheckIn.date',
        'role',
      ]) {
        await expectLater(
            () async => repo.updateFields('u', {'name': 'X', k: 1}),
            throwsArgumentError,
            reason: k);
      }
      final d = (await db.collection('users').doc('u').get()).data()!;
      expect(d['name'], 'Ana');
      expect((d['wallet'] as Map)['stardust'], 5);
    });
  });
}
