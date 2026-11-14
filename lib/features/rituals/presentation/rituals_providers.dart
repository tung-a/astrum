import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/features/rituals/data/events_repository.dart';
import 'package:astrum/features/rituals/domain/ritual_event.dart';

final eventsRepositoryProvider =
    Provider((ref) => EventsRepository(ref.watch(firestoreProvider)));

final eventsProvider = StreamProvider<List<RitualEvent>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(eventsRepositoryProvider).watchEvents(uid);
});
