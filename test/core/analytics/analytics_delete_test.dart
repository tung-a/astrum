import 'package:astrum/core/analytics/analytics_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_firebase.dart';

void main() {
  test('deleteOwnEvents apaga so os eventos do uid (inclui mais de 400)',
      () async {
    final db = FakeFirebaseFirestore();
    for (var i = 0; i < 450; i++) {
      await db
          .collection('analytics_events')
          .add({'eventName': 'x', 'userId': 'u1'});
    }
    await db
        .collection('analytics_events')
        .add({'eventName': 'x', 'userId': 'u2'});
    await db
        .collection('analytics_events')
        .add({'eventName': 'account_delete_completed', 'userId': 'anonymous'});
    final service = AnalyticsService(firestore: db, auth: FakeFirebaseAuth());

    await service.deleteOwnEvents('u1');
    await service.deleteOwnEvents('u1'); // idempotente

    final left = await db.collection('analytics_events').get();
    expect(left.docs.map((d) => d['userId']).toSet(), {'u2', 'anonymous'});
  });
}
