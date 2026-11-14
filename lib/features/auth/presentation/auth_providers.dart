import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/features/auth/data/auth_repository.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';

/// Cadastro/login/logout. Depende so de providers estaveis (nao recria
/// streams).
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FirebaseAuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    profile: ref.watch(profileRepositoryProvider),
  ),
);
