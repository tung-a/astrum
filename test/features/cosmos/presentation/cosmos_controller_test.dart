import 'dart:async';

import 'package:astrum/core/astro/tarot.dart';
import 'package:astrum/features/cosmos/presentation/cosmos_controller.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/make_container.dart';

AppUser _user({String sign = 'Peixes', Map<String, dynamic>? horoscope}) =>
    AppUser(
      uid: 'u1',
      email: 'u1@example.com',
      name: 'Teste',
      zodiacSign: sign,
      dailyHoroscope: horoscope,
    );

void main() {
  late FakeProfileRepository repo;
  late FakeOracleService oracle;

  setUp(() {
    repo = FakeProfileRepository();
    oracle = FakeOracleService(reply: 'horoscopo gerado');
  });

  Future<ProviderContainer> setup(AppUser? user) async {
    final c = await makeContainer(user: user, overrides: [
      profileRepositoryProvider.overrideWithValue(repo),
      oracleServiceProvider.overrideWithValue(oracle),
    ]);
    addTearDown(c.dispose);
    c.listen(cosmosControllerProvider, (_, __) {});
    return c;
  }

  group('ensureHoroscope', () {
    test('gera com o prompt do signo e grava com a data de hoje', () async {
      final c = await setup(_user());

      await c.read(cosmosControllerProvider.notifier).ensureHoroscope();

      expect(oracle.calls, hasLength(1));
      expect(oracle.calls.single.prompt,
          'Gere um horóscopo do dia curto e inspirador para o signo de Peixes. Foco: autoconhecimento. Máximo de 3 frases.');
      expect(oracle.calls.single.sign, 'Peixes');
      expect(repo.horoscopes,
          [(uid: 'u1', date: '2026-11-14', content: 'horoscopo gerado')]);
    });

    test('nao regera quando o horoscopo de hoje ja esta gravado', () async {
      final c = await setup(
          _user(horoscope: {'date': '2026-11-14', 'content': 'ja tenho'}));

      await c.read(cosmosControllerProvider.notifier).ensureHoroscope();

      expect(oracle.calls, isEmpty);
      expect(repo.horoscopes, isEmpty);
    });

    test('regera quando o gravado e de outro dia', () async {
      final c = await setup(
          _user(horoscope: {'date': '2026-11-13', 'content': 'ontem'}));

      await c.read(cosmosControllerProvider.notifier).ensureHoroscope();

      expect(repo.horoscopes, hasLength(1));
    });

    test('segunda chamada na mesma instancia nao refaz', () async {
      final c = await setup(_user());
      final ctl = c.read(cosmosControllerProvider.notifier);

      await ctl.ensureHoroscope();
      await ctl.ensureHoroscope();

      expect(oracle.calls, hasLength(1));
      expect(repo.horoscopes, hasLength(1));
    });

    test('sem signo ou sem perfil nao faz nada', () async {
      final semSigno = await setup(_user(sign: ''));
      await semSigno.read(cosmosControllerProvider.notifier).ensureHoroscope();
      final semPerfil = await setup(null);
      await semPerfil.read(cosmosControllerProvider.notifier).ensureHoroscope();

      expect(oracle.calls, isEmpty);
      expect(repo.horoscopes, isEmpty);
    });

    test('falha do oraculo continua sem tratamento (propaga)', () async {
      final c = await setup(_user());
      oracle.failWith = StateError('falhou');

      await expectLater(
          c.read(cosmosControllerProvider.notifier).ensureHoroscope(),
          throwsStateError);
      expect(repo.horoscopes, isEmpty);
    });
  });

  group('drawTarot', () {
    final card = pickDailyCard(testNow, 'u1');

    test('interpreta pelo oraculo com o prompt da carta e grava', () async {
      oracle.reply = 'interpretacao';
      final c = await setup(_user());

      final msg = await c.read(cosmosControllerProvider.notifier).drawTarot();

      expect(msg, isNull);
      expect(oracle.calls.single.prompt,
          'O usuário tirou a carta de Tarot "${card.name}" para o dia de hoje. Interpretação mística, direta, 2 a 3 frases.');
      expect(repo.tarots, [
        (
          uid: 'u1',
          date: '2026-11-14',
          card: card.name,
          meaning: 'interpretacao'
        )
      ]);
      expect(c.read(cosmosControllerProvider).drawingTarot, isFalse);
    });

    test('se o oraculo falha, grava o significado local da carta', () async {
      oracle.failWith = StateError('falhou');
      final c = await setup(_user());

      final msg = await c.read(cosmosControllerProvider.notifier).drawTarot();

      expect(msg, isNull);
      expect(repo.tarots.single.card, card.name);
      expect(repo.tarots.single.meaning, card.meaning);
    });

    test('falha ao gravar devolve a mensagem e libera drawingTarot', () async {
      repo.saveError = StateError('sem rede');
      final c = await setup(_user());

      final msg = await c.read(cosmosControllerProvider.notifier).drawTarot();

      expect(msg, 'Não foi possível salvar a carta. Tente novamente.');
      expect(c.read(cosmosControllerProvider).drawingTarot, isFalse);
    });

    test('drawingTarot fica true durante e duplo toque e ignorado', () async {
      final gate = Completer<String>();
      oracle.completer = gate;
      final c = await setup(_user());
      final ctl = c.read(cosmosControllerProvider.notifier);

      final first = ctl.drawTarot();
      expect(c.read(cosmosControllerProvider).drawingTarot, isTrue);
      expect(await ctl.drawTarot(), isNull);
      gate.complete('ok');
      await first;

      expect(oracle.calls, hasLength(1));
      expect(repo.tarots, hasLength(1));
      expect(c.read(cosmosControllerProvider).drawingTarot, isFalse);
    });

    test('descartado no meio (apos a interpretacao) nao grava', () async {
      final gate = Completer<String>();
      oracle.completer = gate;
      final c = await makeContainer(user: _user(), overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        oracleServiceProvider.overrideWithValue(oracle),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(cosmosControllerProvider, (_, __) {});
      final future = c.read(cosmosControllerProvider.notifier).drawTarot();

      sub.close();
      await c.pump();
      gate.complete('tarde demais');

      expect(await future, isNull);
      expect(repo.tarots, isEmpty);
    });

    test('sem perfil nao faz nada', () async {
      final c = await setup(null);

      expect(
          await c.read(cosmosControllerProvider.notifier).drawTarot(), isNull);
      expect(oracle.calls, isEmpty);
      expect(repo.tarots, isEmpty);
    });
  });
}
