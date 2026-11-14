import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/core/firebase/rules_contract.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/theme/cosmetics_style.dart';
import 'package:astrum/models/app_user.dart';
import 'package:astrum/models/ritual_event.dart';
import 'package:astrum/models/friend.dart';
import 'package:astrum/models/intention_notice.dart';
import 'package:astrum/services/admin_repository.dart';
import 'package:astrum/services/auth_repository.dart';
import 'package:astrum/services/catalog_repository.dart';
import 'package:astrum/services/chat_store.dart';
import 'package:astrum/models/catalog_entry.dart';
import 'package:astrum/services/economy_repository.dart';
import 'package:astrum/services/events_repository.dart';
import 'package:astrum/services/oracle_service.dart';
import 'package:astrum/services/profile_repository.dart';
import 'package:astrum/services/public_profile_sync.dart';
import 'package:astrum/services/social_repository.dart';

final publicProfileSyncProvider = Provider(
  (ref) => PublicProfileSync(
    db: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  ),
);

final eventsRepositoryProvider =
    Provider((ref) => EventsRepository(ref.watch(firestoreProvider)));

final socialRepositoryProvider =
    Provider((ref) => SocialRepository(ref.watch(firestoreProvider)));

final catalogRepositoryProvider =
    Provider((ref) => CatalogRepository(ref.watch(firestoreProvider)));

final economyRepositoryProvider = Provider<EconomyRepository>(
  (ref) => FirestoreEconomyRepository(
    db: ref.watch(firestoreProvider),
    sync: ref.watch(publicProfileSyncProvider),
  ),
);

final profileRepositoryProvider = Provider(
  (ref) => ProfileRepository(
    db: ref.watch(firestoreProvider),
    sync: ref.watch(publicProfileSyncProvider),
  ),
);

final adminRepositoryProvider =
    Provider((ref) => AdminRepository(ref.watch(firestoreProvider)));

final oracleServiceProvider = Provider((ref) => OracleService());

final chatStoreProvider =
    Provider((ref) => ChatStore(ref.watch(prefsProvider)));

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

/// Catalogo da loja (shop_items): fonte unica de preco e disponibilidade.
final shopCatalogProvider = StreamProvider<Map<String, CatalogEntry>>((ref) {
  return ref.watch(catalogRepositoryProvider).watchShopCatalog();
});

final eventsProvider = StreamProvider<List<RitualEvent>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(eventsRepositoryProvider).watchEvents(uid);
});

final friendsProvider = StreamProvider<List<Friend>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(socialRepositoryProvider).watchFriends(uid);
});

final intentionProvider = StreamProvider<IntentionNotice?>((ref) {
  final uid = ref.watch(currentUidProvider);
  final notificationsEnabled = ref.watch(profileProvider
      .select((p) => p.valueOrNull?.notificationsEnabled ?? false));
  if (uid == null || !notificationsEnabled) return Stream.value(null);
  return ref.watch(socialRepositoryProvider).watchUnreadIntention(uid);
});

final equippedSkinProvider = Provider<SkinStyle>((ref) {
  final id =
      ref.watch(profileProvider).valueOrNull?.equippedSkin ?? defaultSkinId;
  return cosmeticStyles[id] ?? cosmeticStyles[defaultSkinId]!;
});

final equippedBackgroundProvider = Provider<List<Color>>((ref) {
  final id = ref.watch(profileProvider).valueOrNull?.equippedBackground ??
      defaultBackgroundId;
  return cosmeticBackgrounds[id] ?? cosmeticBackgrounds[defaultBackgroundId]!;
});

final pendingOraclePromptProvider = StateProvider<String?>((ref) => null);

/// Cadastro/login/logout. Depende so de providers estaveis (nao recria
/// streams).
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FirebaseAuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    profile: ref.watch(profileRepositoryProvider),
  ),
);
