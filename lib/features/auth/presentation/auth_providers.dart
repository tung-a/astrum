import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/features/auth/data/auth_repository.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Aviso de uma vez na tela de login depois de excluir a conta ("Sua conta foi
/// excluida."). Ligado pelo fim da exclusao; desligado quando o usuario age.
final accountDeletedNoticeProvider = StateProvider<bool>((ref) => false);

/// Cadastro/login/logout. Depende so de providers estaveis (nao recria
/// streams).
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FirebaseAuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    profile: ref.watch(profileRepositoryProvider),
  ),
);
