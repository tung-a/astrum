import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/features/oracle/data/chat_store.dart';
import 'package:astrum/features/oracle/domain/oracle_service.dart';

final oracleServiceProvider = Provider((ref) => OracleService());

final chatStoreProvider =
    Provider((ref) => ChatStore(ref.watch(prefsProvider)));

final pendingOraclePromptProvider = StateProvider<String?>((ref) => null);
