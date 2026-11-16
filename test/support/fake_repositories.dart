import 'dart:async';

import 'package:astrum/core/astro/natal_chart.dart';
import 'package:astrum/features/auth/data/auth_repository.dart';
import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/auth/domain/sign_up_data.dart';
import 'package:astrum/features/economy/domain/equip_slot.dart';
import 'package:astrum/features/profile/data/profile_repository.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/rituals/data/events_repository.dart';
import 'package:astrum/features/rituals/domain/ritual_event.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:astrum/features/social/data/social_repository.dart';
import 'package:astrum/features/social/domain/friend.dart';
import 'package:astrum/features/social/domain/friendship.dart';
import 'package:astrum/features/social/domain/intention_notice.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
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

  /// Emite "perfil ausente" (documento inexistente no servidor).
  void emitMissing(String uid) {
    _last[uid] = null;
    _ctl(uid).add(null);
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

  // Escritas registradas (controllers das telas); falha sob comando.
  final astralMaps = <({String uid, List<PlanetPosition> chart})>[];
  final horoscopes = <({String uid, String date, String content})>[];
  final tarots = <({String uid, String date, String card, String meaning})>[];
  final equips = <({String uid, EquipSlot slot, String itemId})>[];
  Object? saveError;
  Object? equipError;
  final deletedProfiles = <String>[];
  Object? deleteProfileError;

  /// Registro opcional da ordem entre repositorios (testes da exclusao).
  List<String>? log;
  Object? reachableError;
  bool drained = true;
  int drainCalls = 0;

  @override
  Future<void> deleteProfile(String uid) async {
    log?.add('profile.delete');
    if (deleteProfileError != null) throw deleteProfileError!;
    deletedProfiles.add(uid);
  }

  @override
  Future<void> ensureServerReachable(String uid) async {
    log?.add('profile.reachable');
    if (reachableError != null) throw reachableError!;
  }

  @override
  Future<bool> drainPendingWrites() async {
    drainCalls++;
    log?.add('profile.drain');
    return drained;
  }

  @override
  Future<void> saveAstralMap(String uid, List<PlanetPosition> chart) async {
    astralMaps.add((uid: uid, chart: chart));
    if (saveError != null) throw saveError!;
  }

  @override
  Future<void> saveDailyHoroscope(String uid,
      {required String date, required String content}) async {
    horoscopes.add((uid: uid, date: date, content: content));
    if (saveError != null) throw saveError!;
  }

  @override
  Future<void> saveDailyTarot(String uid,
      {required String date,
      required String card,
      required String meaning}) async {
    tarots.add((uid: uid, date: date, card: card, meaning: meaning));
    if (saveError != null) throw saveError!;
  }

  @override
  Future<void> equip(String uid, EquipSlot slot, String itemId) async {
    equips.add((uid: uid, slot: slot, itemId: itemId));
    if (equipError != null) throw equipError!;
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

  final added = <({String uid, RitualEvent event})>[];
  final deletedAll = <String>[];

  List<String>? log;
  Object? deleteError;
  Completer<void>? gate;

  @override
  Future<void> deleteAllEvents(String uid) async {
    log?.add('events.deleteAll');
    if (gate != null) await gate!.future;
    if (deleteError != null) throw deleteError!;
    deletedAll.add(uid);
  }

  final deleted = <({String uid, String eventId})>[];

  @override
  Future<void> addEvent(String uid, RitualEvent event) async {
    added.add((uid: uid, event: event));
  }

  @override
  Future<void> deleteEvent(String uid, String eventId) async {
    deleted.add((uid: uid, eventId: eventId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Fake de [SocialRepository]: registra as assinaturas.
class FakeSocialRepository implements SocialRepository {
  int watchIntentionCalls = 0;

  /// Busca por e-mail: o mapa responde com o Friend cadastrado (ou nada).
  final usersByEmail = <String, Friend>{};
  final searchedEmails = <String>[];
  final intentions = <Map<String, String>>[];
  final deletedReceived = <String>[];
  final deletedSent = <String>[];
  Object? sendError;

  List<String>? log;
  Object? deleteSentError;

  @override
  Future<void> deleteAllReceivedNotifications(String uid) async {
    log?.add('received.deleteAll');
    deletedReceived.add(uid);
  }

  @override
  Future<void> deleteSentIntentions(String uid) async {
    log?.add('sent.delete');
    if (deleteSentError != null) throw deleteSentError!;
    deletedSent.add(uid);
  }

  @override
  Future<Friend?> findUserByEmail(String email) async {
    searchedEmails.add(email);
    return usersByEmail[email];
  }

  @override
  Future<void> sendIntention({
    required String fromUid,
    required String fromName,
    required String toUid,
    required String intentionId,
    required String intentionLabel,
  }) async {
    if (sendError != null) throw sendError!;
    intentions.add({
      'fromUid': fromUid,
      'fromName': fromName,
      'toUid': toUid,
      'intentionId': intentionId,
      'intentionLabel': intentionLabel,
    });
  }

  // ---- amizades com aceite (etapa 12)
  int watchFriendshipsCalls = 0;
  final friendshipsCtl = StreamController<List<Friendship>>.broadcast();
  final requests = <({String me, String myName, String other})>[];
  final actions = <String>[]; // 'accept:u2', 'decline:u2', ...
  final publicNames = <String, String>{};
  RequestOutcome requestOutcome = RequestOutcome.sent;
  ActionOutcome actionOutcome = ActionOutcome.done;

  /// Falha injetada nas escritas (ex.: FirebaseException `unavailable`).
  Object? friendshipError;
  final deletedAllFriendships = <String>[];

  @override
  Stream<List<Friendship>> watchFriendships(String uid) {
    watchFriendshipsCalls++;
    return friendshipsCtl.stream;
  }

  @override
  Future<String?> publicNameOf(String uid) async => publicNames[uid];

  @override
  Future<RequestOutcome> requestFriendship({
    required String me,
    required String myName,
    required String other,
  }) async {
    if (friendshipError != null) throw friendshipError!;
    requests.add((me: me, myName: myName, other: other));
    return requestOutcome;
  }

  Future<ActionOutcome> _record(String what, String other) async {
    if (friendshipError != null) throw friendshipError!;
    actions.add('$what:$other');
    return actionOutcome;
  }

  @override
  Future<ActionOutcome> acceptFriendship(
          {required String me,
          required String myName,
          required String other}) =>
      _record('accept', other);

  @override
  Future<ActionOutcome> declineFriendship(
          {required String me, required String other}) =>
      _record('decline', other);

  @override
  Future<ActionOutcome> removeFriendship(
          {required String me, required String other}) =>
      _record('remove', other);

  @override
  Future<ActionOutcome> cancelRequest(
          {required String me, required String other}) =>
      _record('cancel', other);

  @override
  Future<ActionOutcome> unblock({required String me, required String other}) =>
      _record('unblock', other);

  @override
  Future<void> deleteAllFriendships(String uid) async {
    log?.add('friendships.deleteAll');
    deletedAllFriendships.add(uid);
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

  final resetEmails = <String>[];
  AuthException? resetError;

  @override
  Future<void> sendPasswordReset(String email) async {
    resetEmails.add(email);
    if (resetError != null) throw resetError!;
  }

  final reauthCalls = <String>[];
  int deleteAccountCalls = 0;
  AuthException? reauthError;
  Completer<void>? completerReauth;
  AuthException? deleteAccountError;

  /// Registro opcional da ordem entre repositorios (testes da exclusao).
  List<String>? log;

  @override
  Future<void> reauthenticate(String password) async {
    reauthCalls.add(password);
    log?.add('reauthenticate');
    if (completerReauth != null) await completerReauth!.future;
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    log?.add('deleteAccount');
    if (deleteAccountError != null) throw deleteAccountError!;
  }
}
