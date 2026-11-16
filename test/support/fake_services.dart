import 'dart:async';

import 'package:astrum/core/analytics/analytics_service.dart';
import 'package:astrum/features/economy/data/economy_repository.dart';
import 'package:astrum/features/economy/domain/equip_slot.dart';
import 'package:astrum/features/oracle/domain/oracle_service.dart';

/// Fake de [OracleService]: resposta fixa, falha sob comando e [Completer]
/// opcional para controlar a ordem das respostas.
class FakeOracleService implements OracleService {
  FakeOracleService({this.reply = 'resposta'});

  String reply;
  Object? failWith;
  Completer<String>? completer;
  final calls = <({String prompt, String? sign})>[];

  @override
  Future<String> complete({required String prompt, String? sign}) async {
    calls.add((prompt: prompt, sign: sign));
    if (completer != null) return completer!.future;
    if (failWith != null) throw failWith!;
    return reply;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Fake de [EconomyRepository]: registra os argumentos; erro sob comando.
class FakeEconomyRepository implements EconomyRepository {
  final purchases = <({String uid, String itemId, EquipSlot? equipSlot})>[];
  final checkIns = <({String uid, String today})>[];
  Object? purchaseError;
  Object? checkInError;
  Completer<void>? checkInCompleter;

  @override
  Future<void> purchaseItem({
    required String uid,
    required String itemId,
    EquipSlot? equipSlot,
  }) async {
    purchases.add((uid: uid, itemId: itemId, equipSlot: equipSlot));
    if (purchaseError != null) throw purchaseError!;
  }

  @override
  Future<void> dailyCheckIn(
      {required String uid, required String today}) async {
    checkIns.add((uid: uid, today: today));
    if (checkInCompleter != null) await checkInCompleter!.future;
    if (checkInError != null) throw checkInError!;
  }
}

/// Fake de [AnalyticsService]: lista de eventos.
class FakeAnalytics implements AnalyticsService {
  final events = <String>[];

  @override
  Future<void> logEvent(String eventName) async {
    events.add(eventName);
    log?.add(eventName);
  }

  final deletedOwnEventsOf = <String>[];
  Object? deleteOwnEventsError;

  /// Registro opcional da ordem entre repositorios (testes da exclusao).
  List<String>? log;

  @override
  Future<void> deleteOwnEvents(String uid) async {
    log?.add('analytics.deleteOwn');
    if (deleteOwnEventsError != null) throw deleteOwnEventsError!;
    deletedOwnEventsOf.add(uid);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
