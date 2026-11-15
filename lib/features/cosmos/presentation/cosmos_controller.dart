import 'package:astrum/core/astro/tarot.dart';
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

  CosmosState copyWith({bool? drawingTarot, bool? checkingIn}) => CosmosState(
        drawingTarot: drawingTarot ?? this.drawingTarot,
        checkingIn: checkingIn ?? this.checkingIn,
      );
}

final cosmosControllerProvider =
    NotifierProvider.autoDispose<CosmosController, CosmosState>(
        CosmosController.new);

/// Horoscopo, taro e check-in do dia. Vive e morre com a tela.
class CosmosController extends AutoDisposeNotifier<CosmosState> {
  // Riverpod 2.6 nao tem ref.mounted: o flag evita escrever state (e gravar)
  // depois do dispose, como o State.mounted da tela fazia.
  bool _alive = true;
  bool _horoscopeRequested = false;

  @override
  CosmosState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
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

  /// Tira a carta do dia: interpretacao pelo oraculo (se falhar, usa o
  /// significado local da carta) e gravacao. Retorna a mensagem de falha ao
  /// salvar, ou null. Descartado apos a interpretacao, nao grava.
  Future<String?> drawTarot() async {
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null || state.drawingTarot) return null;
    final oracle = ref.read(oracleServiceProvider);
    final repo = ref.read(profileRepositoryProvider);
    state = state.copyWith(drawingTarot: true);
    try {
      final card = pickDailyCard(ref.read(clockProvider)(), profile.uid);
      var meaning = card.meaning;
      try {
        meaning = await oracle.complete(
          prompt: tarotPrompt(card.name),
          sign: profile.zodiacSign,
        );
      } catch (_) {}
      if (!_alive) return null;
      await repo.saveDailyTarot(
        profile.uid,
        date: _today,
        card: card.name,
        meaning: meaning,
      );
      return null;
    } catch (_) {
      return 'Não foi possível salvar a carta. Tente novamente.';
    } finally {
      if (_alive) state = state.copyWith(drawingTarot: false);
    }
  }
}
