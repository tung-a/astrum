import 'dart:async';

import 'package:astrum/core/firebase/paged_delete.dart';
import 'package:astrum/features/profile/data/profile_repository.dart';
import 'package:astrum/features/profile/data/public_profile_sync.dart';
import 'package:astrum/features/rituals/data/events_repository.dart';
import 'package:astrum/features/social/data/social_repository.dart';
import 'package:astrum/features/social/domain/recipient_unavailable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_firebase.dart';

class _Social extends SocialRepository {
  _Social(super.db, this.error);
  final Object error;

  @override
  Future<void> writeNotification(String toUid, Map<String, dynamic> data) =>
      Future.error(error);
}

class _Profile extends FirestoreProfileRepository {
  _Profile(FirebaseFirestore db, {super.commitTimeout})
      : super(
            db: db, sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth()));

  bool hang = false;
  FirebaseException? failWith;

  @override
  Future<void> commitDelete(WriteBatch batch) {
    if (hang) return Completer<void>().future;
    if (failWith != null) return Future.error(failWith!);
    return super.commitDelete(batch);
  }
}

FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  group('EventsRepository.deleteAllEvents', () {
    test('apaga todos os eventos do uid (mais de 400) e preserva os de outro',
        () async {
      for (var i = 0; i < 450; i++) {
        await db.collection('users/u1/events').add({'title': 't$i'});
      }
      await db.collection('users/u2/events').add({'title': 'outro'});
      final repo = EventsRepository(db);

      await repo.deleteAllEvents('u1');
      await repo.deleteAllEvents('u1'); // idempotente

      expect((await db.collection('users/u1/events').get()).docs, isEmpty);
      expect((await db.collection('users/u2/events').get()).docs, hasLength(1));
    });
  });

  group('SocialRepository: exclusao', () {
    Future<void> seed() async {
      await db.doc('users/u1/friends/f1').set({'name': 'F1'});
      await db.doc('users/u1/friends/f2').set({'name': 'F2'});
      await db.doc('users/u2/friends/f1').set({'name': 'F1 do u2'});
      await db.doc('users/u1/notifications/r1').set({'fromUid': 'u2'});
      // intencoes enviadas por u1 em caixas de terceiros e a de outro remetente
      await db.doc('users/u2/notifications/s1').set({'fromUid': 'u1'});
      await db.doc('users/u3/notifications/s2').set({'fromUid': 'u1'});
      await db.doc('users/u3/notifications/o1').set({'fromUid': 'u2'});
    }

    test('deleteAllFriends e deleteAllReceivedNotifications: so o uid',
        () async {
      await seed();
      final repo = SocialRepository(db);

      await repo.deleteAllFriends('u1');
      await repo.deleteAllReceivedNotifications('u1');

      expect((await db.collection('users/u1/friends').get()).docs, isEmpty);
      expect(
          (await db.collection('users/u1/notifications').get()).docs, isEmpty);
      expect(
          (await db.collection('users/u2/friends').get()).docs, hasLength(1));
      expect((await db.collection('users/u2/notifications').get()).docs,
          hasLength(1));
    });

    test('deleteSentIntentions apaga as enviadas em qualquer caixa (grupo)',
        () async {
      await seed();
      final repo = SocialRepository(db);

      await repo.deleteSentIntentions('u1');

      expect(
          await db.doc('users/u2/notifications/s1').get().then((d) => d.exists),
          isFalse);
      expect(
          await db.doc('users/u3/notifications/s2').get().then((d) => d.exists),
          isFalse);
      // a de outro remetente e a recebida por u1 ficam
      expect(
          await db.doc('users/u3/notifications/o1').get().then((d) => d.exists),
          isTrue);
      expect(
          await db.doc('users/u1/notifications/r1').get().then((d) => d.exists),
          isTrue);
    });

    Future<Object?> send(SocialRepository repo) async {
      try {
        await repo.sendIntention(
            fromUid: 'u1',
            fromName: 'A',
            toUid: 'u2',
            intentionId: 'luz',
            intentionLabel: 'Luz');
        return null;
      } catch (e) {
        return e;
      }
    }

    test('permission-denied sem amizade (ou nao aceita): amizade desfeita',
        () async {
      expect(await send(_Social(db, _denied())),
          isA<RecipientUnavailableException>());
      await db.doc('friendships/u1_u2').set({'status': 'pending'});
      expect(await send(_Social(db, _denied())),
          isA<RecipientUnavailableException>());
      await db.doc('friendships/u1_u2').set({'status': 'declined'});
      expect(await send(_Social(db, _denied())),
          isA<RecipientUnavailableException>());
    });

    test('permission-denied com amizade aceita: erro original', () async {
      await db.doc('friendships/u1_u2').set({'status': 'accepted'});
      expect(await send(_Social(db, _denied())), isA<FirebaseException>());
    });

    test('outro erro sobe como esta', () async {
      final e =
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      expect(await send(_Social(db, e)), same(e));
    });
  });

  group('ProfileRepository.deleteProfile', () {
    Future<void> seed() async {
      await db.doc('users/u1').set({'name': 'A'});
      await db.doc('publicProfiles/u1').set({'name': 'A'});
      await db.doc('users/u2').set({'name': 'B'});
      await db.doc('publicProfiles/u2').set({'name': 'B'});
    }

    test('apaga users e publicProfiles do uid, preserva o outro, idempotente',
        () async {
      await seed();
      final repo = _Profile(db);

      await repo.deleteProfile('u1');
      await repo.deleteProfile('u1');

      expect(await db.doc('users/u1').get().then((d) => d.exists), isFalse);
      expect(await db.doc('publicProfiles/u1').get().then((d) => d.exists),
          isFalse);
      expect(await db.doc('users/u2').get().then((d) => d.exists), isTrue);
      expect(await db.doc('publicProfiles/u2').get().then((d) => d.exists),
          isTrue);
    });

    test('commit que nao completa: ServerOfflineException', () async {
      await seed();
      final repo = _Profile(db, commitTimeout: const Duration(milliseconds: 20))
        ..hang = true;
      await expectLater(
          repo.deleteProfile('u1'), throwsA(isA<ServerOfflineException>()));
    });

    test('unavailable vira offline; permission-denied sobe', () async {
      final repo = _Profile(db)
        ..failWith =
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      await expectLater(
          repo.deleteProfile('u1'), throwsA(isA<ServerOfflineException>()));
      repo.failWith = _denied();
      await expectLater(
          repo.deleteProfile('u1'),
          throwsA(isA<FirebaseException>()
              .having((e) => e.code, 'code', 'permission-denied')));
    });
  });
}
