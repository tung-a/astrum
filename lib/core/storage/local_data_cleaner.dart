import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Limpeza de dados locais ao sair ou excluir a conta (etapa 11).
///
/// O cache do Firestore (conversas, perfil) fica no aparelho. Limpa-lo exige
/// `clearPersistence()`, que so funciona antes de qualquer uso da instancia;
/// por isso a limpeza e FEITA NA PROXIMA PARTIDA A FRIO, marcada por uma flag
/// (sem dado pessoal) em `shared_preferences`. Nao se usa `terminate()` em
/// sessao: reutilizar o Firestore depois dele e arriscado.
class LocalDataCleaner {
  const LocalDataCleaner(this._prefs);

  final SharedPreferences _prefs;

  static const pendingKey = 'astrum.wipeCachePending';

  /// Ha limpeza do cache do Firestore pendente para a proxima partida.
  bool get isCacheWipePending => _prefs.getBool(pendingKey) ?? false;

  Future<void> markCacheWipePending() => _prefs.setBool(pendingKey, true);

  /// Chamada em `main`, depois de `Firebase.initializeApp` e ANTES de qualquer
  /// uso do Firestore. Se der certo remove a flag; se falhar (ex.:
  /// `failed-precondition`) ou estourar [timeout], a flag fica para a proxima
  /// partida (se a limpeza terminar depois do prazo, a flag e removida) e o
  /// app abre normalmente. Nunca lanca.
  Future<bool> runPendingCacheWipe(
    FirebaseFirestore db, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!isCacheWipePending) return false;
    final wipe = db.clearPersistence();
    try {
      await wipe.timeout(timeout);
      await _prefs.remove(pendingKey);
      return true;
    } on TimeoutException {
      // A limpeza nativa pode concluir depois do prazo. Se concluir, remove a
      // flag: sem isso o app limparia de novo na proxima partida e perderia
      // escritas offline de um novo usuario. Sem await: nao trava a partida.
      unawaited(wipe.then<void>((_) async {
        try {
          await _prefs.remove(pendingKey);
        } catch (_) {}
      }, onError: (Object _) {}));
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Escritas locais pendentes subiram ao servidor em ate [timeout]?
  /// Offline estoura o prazo e devolve false (nada e perdido).
  static Future<bool> drainPendingWrites(
    FirebaseFirestore db, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      await db.waitForPendingWrites().timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fim da conta (exclusao): apaga tudo de `shared_preferences` e deixa so a
  /// flag de limpeza do cache para a proxima partida a frio.
  ///
  /// Grava a flag ANTES de limpar e remove as demais chaves uma a uma, para
  /// nao haver janela sem flag (um kill entre os dois passos perderia a
  /// limpeza do cache).
  Future<void> wipeOnAccountEnd() async {
    await markCacheWipePending();
    for (final k in _prefs.getKeys().toList()) {
      if (k != pendingKey) await _prefs.remove(k);
    }
  }

  /// Logout: drena as escritas pendentes; so marca a limpeza se drenou (se
  /// estourou, o cache fica e as pendencias sobrevivem). Devolve se marcou.
  Future<bool> prepareLogout(FirebaseFirestore db) async {
    final drained = await drainPendingWrites(db);
    if (drained) await markCacheWipePending();
    return drained;
  }
}
