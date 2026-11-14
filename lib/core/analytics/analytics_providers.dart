import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/core/analytics/analytics_service.dart';
import 'package:astrum/core/firebase/firebase_providers.dart';

final analyticsServiceProvider = Provider(
  (ref) => AnalyticsService(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  ),
);
