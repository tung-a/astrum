import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/firebase/firebase_providers.dart';
import '../data/cosmetics.dart';
import '../models/app_user.dart';
import '../services/admin_repository.dart';
import '../services/analytics_service.dart';
import '../services/auth_repository.dart';
import '../services/catalog_repository.dart';
import '../services/chat_store.dart';
import '../services/economy.dart';
import '../services/economy_repository.dart';
import '../services/events_repository.dart';
import '../services/oracle_service.dart';
import '../services/profile_repository.dart';
import '../services/public_profile_sync.dart';
import '../services/social_repository.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

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

final analyticsServiceProvider = Provider(
  (ref) => AnalyticsService(
    firestore: ref.watch(firestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  ),
);

final prefsProvider = Provider<SharedPreferences>((ref) {
  throw StateError('prefs not overridden');
});

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

/// uid do usuario logado. Os providers de streams por usuario dependem so
/// disto (via `select`), para nao reabrir listeners quando saldo, horoscopo
/// ou itens equipados mudam em `users/{uid}`.
final currentUidProvider = Provider<String?>((ref) {
  // Vem da auth, nao do perfil: durante o loading do perfil de outro usuario o
  // valueOrNull do perfil ainda retem o anterior. AsyncError tambem retem o
  // valor anterior, entao hasError e testado primeiro (erro conta como null).
  return ref.watch(authStateProvider.select(
    (a) => a.hasError ? null : a.valueOrNull?.uid,
  ));
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
      ref.watch(profileProvider).valueOrNull?.equippedSkin ?? 'skin_classic';
  return cosmeticStyles[id] ?? cosmeticStyles['skin_classic']!;
});

final equippedBackgroundProvider = Provider<List<Color>>((ref) {
  final id =
      ref.watch(profileProvider).valueOrNull?.equippedBackground ?? 'bg_void';
  return cosmeticBackgrounds[id] ?? cosmeticBackgrounds['bg_void']!;
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
