import 'dart:async';

import 'package:astrum/models/app_user.dart';
import 'package:astrum/models/ritual_event.dart';
import 'package:astrum/models/friend.dart';
import 'package:astrum/models/intention_notice.dart';
import 'package:astrum/models/auth_exception.dart';
import 'package:astrum/models/sign_up_data.dart';
import 'package:astrum/services/auth_repository.dart';
import 'package:astrum/providers/app_providers.dart';
import 'package:astrum/services/events_repository.dart';
import 'package:astrum/services/profile_repository.dart';
import 'package:astrum/services/social_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fake de [ProfileRepository]: perfil controlavel por uid e contagem de
/// assinaturas. Cada [watchProfile] e uma assinatura independente (como o
/// snapshot real); [activeProfileListeners] mostra quais uids ainda estao
/// assinados.
class FakeProfileRepository implements ProfileRepository {
  final _profiles = <String, StreamController<AppUser?>>{};
  final _last = <String, AppUser?>{};
  final profileWatchedUids = <String>[];
  final activeProfileListeners = <String>{};

  StreamController<AppUser?> _ctl(String uid) => _profiles.putIfAbsent(
      uid, () => StreamController<AppUser?>.broadcast(sync: true));

  /// Emite o perfil (guarda o ultimo valor e o reenvia a quem assinar depois,
  /// como o Firestore).
  void emit(AppUser user) {
    _last[user.uid] = user;
    _ctl(user.uid).add(user);
  }

  @override
  Stream<AppUser?> watchProfile(User user) {
    final uid = user.uid;
    profileWatchedUids.add(uid);
    return Stream<AppUser?>.multi((c) {
      activeProfileListeners.add(uid);
      if (_last.containsKey(uid)) c.add(_last[uid]);
      final sub = _ctl(uid).stream.listen(c.add);
      c.onCancel = () {
        activeProfileListeners.remove(uid);
        return sub.cancel();
      };
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Fake de [EventsRepository]: registra as assinaturas.
class FakeEventsRepository implements EventsRepository {
  int watchCalls = 0;
  final uids = <String>[];

  @override
  Stream<List<RitualEvent>> watchEvents(String uid) {
    watchCalls++;
    uids.add(uid);
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Fake de [SocialRepository]: registra as assinaturas.
class FakeSocialRepository implements SocialRepository {
  int watchFriendsCalls = 0;
  int watchIntentionCalls = 0;

  @override
  Stream<List<Friend>> watchFriends(String uid) {
    watchFriendsCalls++;
    return const Stream.empty();
  }

  @override
  Stream<IntentionNotice?> watchUnreadIntention(String uid) {
    watchIntentionCalls++;
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Conjunto de fakes por repositorio, com os overrides prontos.
class FakeRepos {
  FakeRepos();

  final profile = FakeProfileRepository();
  final events = FakeEventsRepository();
  final social = FakeSocialRepository();

  List<Override> get overrides => [
        profileRepositoryProvider.overrideWithValue(profile),
        eventsRepositoryProvider.overrideWithValue(events),
        socialRepositoryProvider.overrideWithValue(social),
      ];
}

AppUser testUser({
  String uid = 'u1',
  int stardust = 500,
  String role = 'user',
  bool notificationsEnabled = true,
  String equippedSkin = 'skin_classic',
}) =>
    AppUser(
      uid: uid,
      email: '$uid@example.com',
      name: 'Teste',
      role: role,
      stardust: stardust,
      notificationsEnabled: notificationsEnabled,
      equippedSkin: equippedSkin,
    );

/// Fake de [AuthRepository]: registra chamadas, falha configuravel e
/// `completer` opcional para segurar o register (testa inFlight).
class FakeAuthRepository implements AuthRepository {
  final signInCalls = <({String email, String password})>[];
  final registerCalls = <SignUpData>[];
  int signOutCalls = 0;
  AuthException? failWith;
  Completer<void>? completer;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls.add((email: email, password: password));
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> register(SignUpData data) async {
    registerCalls.add(data);
    if (completer != null) await completer!.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> signOut() async => signOutCalls++;
}
