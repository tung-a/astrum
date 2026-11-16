import 'package:astrum/core/storage/local_data_cleaner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final prefsProvider = Provider<SharedPreferences>((ref) {
  throw StateError('prefs not overridden');
});

/// Limpeza de dados locais ao sair ou excluir a conta.
final localDataCleanerProvider =
    Provider((ref) => LocalDataCleaner(ref.watch(prefsProvider)));
