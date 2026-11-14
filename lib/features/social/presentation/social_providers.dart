import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/social/data/social_repository.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/intention_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final socialRepositoryProvider =
    Provider((ref) => SocialRepository(ref.watch(firestoreProvider)));

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
