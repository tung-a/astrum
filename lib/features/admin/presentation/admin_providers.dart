import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/features/admin/data/admin_repository.dart';

final adminRepositoryProvider =
    Provider((ref) => AdminRepository(ref.watch(firestoreProvider)));
