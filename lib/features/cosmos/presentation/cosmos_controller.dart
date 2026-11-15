import 'package:astrum/core/clock/clock_providers.dart';
import 'package:astrum/core/clock/day_key.dart';
import 'package:astrum/features/cosmos/domain/daily_content.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CosmosState {
  const CosmosState({this.drawingTarot = false, this.checkingIn = false});
  final bool drawingTarot;
  final bool checkingIn;
}

final cosmosControllerProvider =
    NotifierProvider.autoDispose<CosmosController, CosmosState>(
        CosmosController.new);

/// Horoscopo, taro e check-in do dia. Vive e morre com a tela.
class CosmosController extends AutoDisposeNotifier<CosmosState> {
  bool _horoscopeRequested = false;

  @override
  CosmosState build() {
    return const CosmosState();
  }

  String get _today => dayKey(ref.read(clockProvider)());

  /// Gera e grava o horoscopo do dia uma vez por instancia (o flag e marcado
  /// quando ha signo, mesmo com o horoscopo de hoje ja gravado). Excecoes
  /// continuam sem tratamento (comportamento de antes; divida registrada).
  Future<void> ensureHoroscope() async {
    if (_horoscopeRequested) return;
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null || profile.zodiacSign.isEmpty) return;
    _horoscopeRequested = true;
    final today = _today;
    if (!needsHoroscope(profile, today)) return;
    // Lidos antes do await: a gravacao segue mesmo se a tela sair (como antes).
    final oracle = ref.read(oracleServiceProvider);
    final repo = ref.read(profileRepositoryProvider);
    final text = await oracle.complete(
      prompt: horoscopePrompt(profile.zodiacSign),
      sign: profile.zodiacSign,
    );
    await repo.saveDailyHoroscope(profile.uid, date: today, content: text);
  }
}
