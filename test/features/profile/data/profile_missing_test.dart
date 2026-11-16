import 'dart:async';

import 'package:astrum/features/profile/data/profile_repository.dart';
import 'package:astrum/features/profile/data/public_profile_sync.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_firebase.dart';

typedef _Snap = ({bool exists, bool fromCache, Map<String, dynamic>? data});

void main() {
  group('mapProfileSnapshots', () {
    late StreamController<_Snap> snaps;
    late List<AppUser?> out;
    late StreamSubscription<AppUser?> sub;

    setUp(() {
      snaps = StreamController<_Snap>();
      out = [];
      sub = FirestoreProfileRepository.mapProfileSnapshots(snaps.stream,
              uid: 'u1', email: 'a@b.c', displayName: 'Luna')
          .listen(out.add);
    });
    tearDown(() async {
      await sub.cancel();
      unawaited(snaps.close());
    });

    Future<void> push(bool exists, bool fromCache,
        [Map<String, dynamic>? d]) async {
      snaps.add((exists: exists, fromCache: fromCache, data: d));
      await pumpEventQueue();
    }

    test('inexistente so do cache (offline sem cache): nao emite', () async {
      await push(false, true);
      expect(out, isEmpty);
    });

    test('inexistente do servidor: emite null (perfil ausente) uma vez',
        () async {
      await push(false, true);
      await push(false, false);
      await push(false, false); // mudanca so de metadados
      expect(out, [null]);
    });

    test(
        'cadastro gravado offline (existe, pendente no cache) continua emitindo',
        () async {
      await push(true, true, {
        'name': 'Luna',
        'wallet': {'stardust': 500}
      });
      expect(out, hasLength(1));
      expect(out.single, isA<AppUser>());
      expect(out.single!.stardust, 500);
    });

    test('mudanca so de metadados (cache -> servidor) nao reemite', () async {
      final d = {
        'name': 'Luna',
        'wallet': {'stardust': 500}
      };
      await push(true, true, d);
      await push(true, false, {
        'name': 'Luna',
        'wallet': {'stardust': 500}
      });
      expect(out, hasLength(1));
      await push(true, false, {
        'name': 'Luna',
        'wallet': {'stardust': 450}
      });
      expect(out, hasLength(2));
      expect(out.last!.stardust, 450);
    });

    test('existia e foi apagado (outro aparelho): emite null', () async {
      await push(true, false, {'name': 'Luna'});
      await push(false, false);
      expect(out.map((u) => u == null), [false, true]);
    });

    test('apagado e recriado volta a emitir o perfil', () async {
      await push(false, false);
      await push(true, false, {'name': 'Luna'});
      expect(out.map((u) => u == null), [true, false]);
    });
  });

  test('watchProfile sobre o Firestore: ausente -> null; existe -> perfil',
      () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreProfileRepository(
        db: db, sync: PublicProfileSync(db: db, auth: FakeFirebaseAuth()));
    final user = FakeUser('u1');
    final out = <AppUser?>[];
    final sub = repo.watchProfile(user).listen(out.add);
    await pumpEventQueue();
    expect(out, [null]);

    await db.doc('users/u1').set({
      'name': 'Luna',
      'wallet': {'stardust': 500}
    });
    await pumpEventQueue();
    expect(out.last?.name, 'Luna');

    await db.doc('users/u1').delete();
    await pumpEventQueue();
    expect(out.last, isNull);
    await sub.cancel();
  });
}
