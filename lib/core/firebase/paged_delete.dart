import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Operacao que exige o servidor (leitura de pagina ou commit de exclusao)
/// tentada sem conexao. Nada alem do que ja foi apagado muda; repetir e seguro.
class ServerOfflineException implements Exception {
  const ServerOfflineException();
  @override
  String toString() =>
      'ServerOfflineException: sem conexao com o servidor; repita para concluir.';
}

/// Le uma pagina da consulta. O padrao le SEMPRE do servidor (exclusao nao
/// pode se basear em cache parcial).
typedef ServerPageReader = Future<QuerySnapshot<Map<String, dynamic>>> Function(
    Query<Map<String, dynamic>> query);

/// Confirma o lote de exclusao.
typedef BatchCommitter = Future<void> Function(WriteBatch batch);

Future<QuerySnapshot<Map<String, dynamic>>> readServerPage(
    Query<Map<String, dynamic>> query) async {
  try {
    return await query.get(const GetOptions(source: Source.server));
  } on FirebaseException catch (e) {
    if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
      throw const ServerOfflineException();
    }
    rethrow;
  }
}

Future<void> _commit(WriteBatch batch) => batch.commit();

/// Apaga TUDO o que a [query] devolve: le uma pagina do servidor, apaga em
/// batch e repete ate uma pagina vazia. Idempotente e sem estado (retomar e so
/// rodar de novo: consulta ja vazia custa 1 leitura). Offline (leitura que
/// falha ou commit que nao completa em [commitTimeout]) lanca
/// [ServerOfflineException]; outros erros (ex.: `resource-exhausted`,
/// `permission-denied`) sobem como estao. Devolve os ids apagados, no maximo
/// [maxIds] (so para auditoria/varredura; o apagamento nao e limitado).
///
/// [readPage] e [commit] so existem para teste.
Future<List<String>> deleteQueryPaged(
  Query<Map<String, dynamic>> query, {
  int page = 400,
  Duration commitTimeout = const Duration(seconds: 15),
  int maxIds = 1000,
  ServerPageReader readPage = readServerPage,
  BatchCommitter commit = _commit,
}) async {
  final ids = <String>[];
  while (true) {
    final snap = await readPage(query.limit(page));
    if (snap.docs.isEmpty) break;
    final batch = query.firestore.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    try {
      await commit(batch).timeout(commitTimeout);
    } on TimeoutException {
      // Offline o commit nao completa; a nova tentativa e idempotente.
      throw const ServerOfflineException();
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        throw const ServerOfflineException();
      }
      rethrow;
    }
    for (final d in snap.docs) {
      if (ids.length < maxIds) ids.add(d.id);
    }
  }
  return ids;
}
