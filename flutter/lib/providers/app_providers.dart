import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/cosmetics.dart';
import '../models/app_user.dart';
import '../services/chat_store.dart';
import '../services/oracle_service.dart';
import '../services/user_repository.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final userRepositoryProvider = Provider((ref) => UserRepository());

final oracleServiceProvider = Provider((ref) => OracleService());

final prefsProvider = Provider<SharedPreferences>((ref) {
  throw StateError('prefs not overridden');
});

final chatStoreProvider = Provider((ref) => ChatStore(ref.watch(prefsProvider)));

final profileProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(userRepositoryProvider).watchProfile();
});

final eventsProvider = StreamProvider<List<RitualEvent>>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  if (profile == null) return Stream.value(const []);
  return ref.watch(userRepositoryProvider).watchEvents(profile.uid);
});

final friendsProvider = StreamProvider<List<Friend>>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  if (profile == null) return Stream.value(const []);
  return ref.watch(userRepositoryProvider).watchFriends(profile.uid);
});

final intentionProvider = StreamProvider<IntentionNotice?>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  if (profile == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watchUnreadIntention(profile.uid);
});

final equippedSkinProvider = Provider<SkinStyle>((ref) {
  final id = ref.watch(profileProvider).valueOrNull?.equippedSkin ?? 'skin_classic';
  return cosmeticStyles[id] ?? cosmeticStyles['skin_classic']!;
});

final pendingOraclePromptProvider = StateProvider<String?>((ref) => null);
