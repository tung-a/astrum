import 'dart:async';

import 'package:astrum/core/storage/local_data_cleaner.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Db extends FakeFirebaseFirestore {
  int clears = 0;
  Object? clearError;
  Future<void>? pending;
  Completer<void>? clearGate;

  @override
  Future<void> clearPersistence() async {
    clears++;
    if (clearError != null) throw clearError!;
    await clearGate?.future;
  }

  @override
  Future<void> waitForPendingWrites() => pending ?? Future.value();
}

void main() {
  Future<SharedPreferences> prefs([Map<String, Object> init = const {}]) async {
    SharedPreferences.setMockInitialValues(init);
    return SharedPreferences.getInstance();
  }

  test('sem flag: nao limpa nada', () async {
    final db = _Db();
    final c = LocalDataCleaner(await prefs());
    expect(await c.runPendingCacheWipe(db), isFalse);
    expect(db.clears, 0);
  });

  test('com flag: limpa o cache e remove a flag', () async {
    final db = _Db();
    final sp = await prefs({LocalDataCleaner.pendingKey: true});
    final c = LocalDataCleaner(sp);
    expect(c.isCacheWipePending, isTrue);
    expect(await c.runPendingCacheWipe(db), isTrue);
    expect(db.clears, 1);
    expect(c.isCacheWipePending, isFalse);
  });

  test('falha ao limpar: a flag fica para a proxima partida e nao lanca',
      () async {
    final db = _Db()..clearError = StateError('failed-precondition');
    final sp = await prefs({LocalDataCleaner.pendingKey: true});
    final c = LocalDataCleaner(sp);
    expect(await c.runPendingCacheWipe(db), isFalse);
    expect(c.isCacheWipePending, isTrue);
  });

  test('clearPersistence que nao termina: flag fica e nao lanca', () async {
    final db = _Db()..clearGate = Completer<void>();
    final sp = await prefs({LocalDataCleaner.pendingKey: true});
    final c = LocalDataCleaner(sp);
    expect(
        await c.runPendingCacheWipe(db,
            timeout: const Duration(milliseconds: 20)),
        isFalse);
    expect(c.isCacheWipePending, isTrue);
  });

  test('wipeOnAccountEnd apaga prefs e deixa so a flag', () async {
    final sp = await prefs({
      'astrum.chat.notice.u1': true,
      'astrum.outra': 'x',
    });
    final c = LocalDataCleaner(sp);
    await c.wipeOnAccountEnd();
    expect(sp.getKeys(), {LocalDataCleaner.pendingKey});
    expect(c.isCacheWipePending, isTrue);
  });

  test('logout: drenou marca a limpeza; estourou o prazo nao marca', () async {
    final db = _Db();
    final c = LocalDataCleaner(await prefs());
    expect(await c.prepareLogout(db), isTrue);
    expect(c.isCacheWipePending, isTrue);

    final sp2 = await prefs();
    final c2 = LocalDataCleaner(sp2);
    db.pending = Future<void>.delayed(const Duration(seconds: 30));
    expect(
        await LocalDataCleaner.drainPendingWrites(db,
            timeout: const Duration(milliseconds: 20)),
        isFalse);
    expect(c2.isCacheWipePending, isFalse);
  });
}
