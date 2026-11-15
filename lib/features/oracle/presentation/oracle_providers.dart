import 'package:astrum/core/firebase/firebase_providers.dart';
import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/features/oracle/data/chat_notice_store.dart';
import 'package:astrum/features/oracle/data/chat_repository.dart';
import 'package:astrum/features/oracle/data/firestore_chat_repository.dart';
import 'package:astrum/features/oracle/domain/oracle_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final oracleServiceProvider = Provider((ref) => OracleService());

final firestoreChatRepositoryProvider = Provider<ChatRepository>(
    (ref) => FirestoreChatRepository(ref.watch(firestoreProvider)));

/// Repositorio do historico do oraculo (Firestore; testes trocam por fake).
final chatRepositoryProvider = Provider<ChatRepository>(
    (ref) => ref.watch(firestoreChatRepositoryProvider));

final chatNoticeStoreProvider =
    Provider((ref) => ChatNoticeStore(ref.watch(prefsProvider)));

final pendingOraclePromptProvider = StateProvider<String?>((ref) => null);
