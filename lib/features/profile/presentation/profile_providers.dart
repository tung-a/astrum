import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/features/profile/data/profile_repository.dart';
import 'package:astrum/features/profile/data/public_profile_sync.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final publicProfileSyncProvider = Provider(
  (ref) => PublicProfileSync(
    db: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  ),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => FirestoreProfileRepository(
    db: ref.watch(firestoreProvider),
    sync: ref.watch(publicProfileSyncProvider),
  ),
);

/// Exclusao de conta em andamento (a cascata esta rodando): suprime os
/// redirects do router, como o cadastro em andamento. Quem liga e desliga e o
/// DeleteAccountController.
final deletionInFlightProvider = StateProvider<bool>((ref) => false);

/// Perfil do usuario logado. Semantica switchMap: ao mudar o estado de auth
/// (logout, login de outro usuario) o provider e reconstruido e o Riverpod
/// cancela a assinatura anterior antes de abrir a do novo uid.
final profileProvider = StreamProvider<AppUser?>((ref) {
  final auth = ref.watch(authStateProvider);
  // Erro no stream de auth conta como deslogado.
  if (auth.hasError) return Stream<AppUser?>.value(null);
  // Aguardando o primeiro estado de auth: perfil em loading.
  if (!auth.hasValue) return const Stream<AppUser?>.empty();
  final user = auth.requireValue;
  if (user == null) return Stream<AppUser?>.value(null);
  return ref.watch(profileRepositoryProvider).watchProfile(user);
});
