import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:astrum/core/firebase/firestore_paths.dart';
import 'package:astrum/features/rituals/domain/ritual_event.dart';

/// Eventos/rituais em users/{uid}/events.
class EventsRepository {
  EventsRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.userDoc(uid);

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
}
