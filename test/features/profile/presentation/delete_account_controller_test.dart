import 'dart:async';

import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/core/firebase/paged_delete.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/core/storage/local_data_cleaner.dart';
import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/auth/presentation/auth_providers.dart';
import 'package:astrum/features/oracle/data/chat_repository.dart';
import 'package:astrum/features/oracle/domain/chat_models.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:astrum/features/profile/presentation/delete_account_controller.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_repositories.dart';
import '../../../support/fake_services.dart';
import '../../../support/in_memory_chat_repository.dart';
import '../../../support/make_container.dart';

class _LogChat extends InMemoryChatRepository {
  _LogChat(this.log);
  final List<String> log;
  Object? error;

  @override
  Future<List<String>> deleteAllConversations(String uid) async {
    log.add('chat.deleteAll');
    if (error != null) throw error!;
    return super.deleteAllConversations(uid);
  }

  @override
  Future<void> deleteConversation(String uid, String convId) async {
    log.add('chat.delete:$convId');
    return super.deleteConversation(uid, convId);
  }
}

const _secret = 'SENHA-SECRETA-123';

final _testUid = StateProvider<String?>((ref) => 'u1');

void main() {
  late List<String> log;
  late FakeAuthRepository auth;
  late FakeProfileRepository profile;
  late FakeEventsRepository events;
  late FakeSocialRepository social;
  late FakeAnalytics analytics;
  late _LogChat chat;
  late SharedPreferences prefs;
  late ProviderContainer c;

  setUp(() async {
    log = [];
    auth = FakeAuthRepository()..log = log;
    profile = FakeProfileRepository()..log = log;
    events = FakeEventsRepository()..log = log;
    social = FakeSocialRepository()..log = log;
    analytics = FakeAnalytics()..log = log;
    chat = _LogChat(log);
    SharedPreferences.setMockInitialValues({
      'astrum.chat.notice.u1': true,
      'astrum.outra': 'x',
    });
    prefs = await SharedPreferences.getInstance();
    // duas conversas (para a varredura final)
    for (final id in ['a', 'b']) {
      await chat.appendMessage('u1',
          convId: id,
          message: ChatTurnStored(
              id: 'm', role: 'user', text: 'x', createdAt: DateTime(2026)),
          updatedAt: DateTime(2026),
          isNew: true);
    }
    c = await makeContainer(user: testUser(), overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(profile),
      chatRepositoryProvider.overrideWithValue(chat),
      eventsRepositoryProvider.overrideWithValue(events),
      socialRepositoryProvider.overrideWithValue(social),
      analyticsServiceProvider.overrideWithValue(analytics),
      prefsProvider.overrideWithValue(prefs),
      currentUidProvider.overrideWith((ref) => ref.watch(_testUid)),
    ]);
    addTearDown(c.dispose);
  });

  DeleteAccountController ctl() =>
      c.read(deleteAccountControllerProvider.notifier);
  DeleteAccountState st() => c.read(deleteAccountControllerProvider);

  FirebaseException fb(String code) =>
      FirebaseException(plugin: 'cloud_firestore', code: code);

  const fullOrder = [
    'reauthenticate',
    'profile.reachable',
    'profile.drain',
    'profile.delete',
    'chat.deleteAll',
    'events.deleteAll',
    'friends.deleteAll',
    'received.deleteAll',
    'sent.delete',
    'analytics.deleteOwn',
    // varredura final
    'chat.delete:a',
    'chat.delete:b',
    'chat.deleteAll',
    'events.deleteAll',
    'friends.deleteAll',
    'received.deleteAll',
    'deleteAccount',
    'account_delete_completed',
  ];

  test('caminho feliz: ordem dos passos, varredura final e Auth por ultimo',
      () async {
    await ctl().run(_secret);

    expect(st().phase, DeletePhase.done);
    expect(
        log.map((e) => e.startsWith('chat.delete:') ? e : e).toList()..sort(),
        [...fullOrder]..sort());
    // ordem relativa essencial
    int at(String e, [int from = 0]) => log.indexOf(e, from);
    expect(at('reauthenticate'), 0);
    expect(at('profile.delete') > at('profile.drain'), isTrue);
    expect(at('chat.deleteAll') > at('profile.delete'), isTrue);
    expect(at('analytics.deleteOwn') > at('sent.delete'), isTrue);
    expect(at('deleteAccount'), log.length - 2);
    expect(log.last, 'account_delete_completed');
    // conversas antes de eventos, amigos, notificacoes, enviadas, analytics
    final seq = [
      'profile.delete',
      'chat.deleteAll',
      'events.deleteAll',
      'friends.deleteAll',
      'received.deleteAll',
      'sent.delete',
      'analytics.deleteOwn',
    ].map(at).toList();
    expect(seq, [...seq]..sort());
    // varredura passa pelas duas conversas apagadas
    expect(log.where((e) => e.startsWith('chat.delete:')).toSet(),
        {'chat.delete:a', 'chat.delete:b'});
    expect(auth.reauthCalls, [_secret]);
    expect(auth.deleteAccountCalls, 1);
    expect(profile.deletedProfiles, ['u1']);
  });

  test('fim: prefs limpas so com a flag de limpeza; aviso ligado; sem fluxo',
      () async {
    await ctl().run(_secret);

    expect(prefs.getKeys(), {LocalDataCleaner.pendingKey});
    expect(c.read(accountDeletedNoticeProvider), isTrue);
    expect(c.read(deletionInFlightProvider), isFalse);
    expect(analytics.events, ['account_delete_completed']);
  });

  test('flag de limpeza do cache e gravada antes de apagar qualquer dado',
      () async {
    profile.deleteProfileError = fb('unavailable');
    await ctl().run(_secret);
    expect(st().phase, DeletePhase.failed);
    expect(prefs.getBool(LocalDataCleaner.pendingKey), isTrue);
  });

  test('senha incorreta: nada e apagado e a mensagem diz isso', () async {
    auth.reauthError = const AuthException(AuthErrorCode.invalidCredentials);
    await ctl().run(_secret);

    expect(st().phase, DeletePhase.failed);
    expect(st().failure, DeleteFailureKind.wrongPassword);
    expect(st().message, 'Senha incorreta. Nada foi apagado.');
    expect(log, ['reauthenticate']);
    expect(st().dataDeleted, isFalse);
    expect(c.read(deletionInFlightProvider), isFalse);
  });

  test('muitas tentativas na reautenticacao', () async {
    auth.reauthError = const AuthException(AuthErrorCode.tooManyRequests);
    await ctl().run(_secret);
    expect(st().failure, DeleteFailureKind.tooManyRequests);
    expect(st().message,
        'Muitas tentativas. Aguarde alguns minutos e tente de novo.');
  });

  test('servidor inalcancavel na pre-condicao: aborta sem apagar nada',
      () async {
    profile.reachableError = const ServerOfflineException();
    await ctl().run(_secret);

    expect(st().failure, DeleteFailureKind.offline);
    expect(st().failedStep, DeleteStep.verifying);
    expect(log, ['reauthenticate', 'profile.reachable']);
    expect(prefs.getBool(LocalDataCleaner.pendingKey), isNull);
    expect(st().message, contains('Sem conexão'));
  });

  group('falha em cada passo e retomada', () {
    final cases = <(String, DeleteStep, void Function(Object?))>[
      ('perfil', DeleteStep.profile, (e) => profile.deleteProfileError = e),
      ('conversas', DeleteStep.conversations, (e) => chat.error = e),
      ('eventos', DeleteStep.events, (e) => events.deleteError = e),
      (
        'intencoes enviadas',
        DeleteStep.sentIntentions,
        (e) => social.deleteSentError = e
      ),
      (
        'registros de uso',
        DeleteStep.usageRecords,
        (e) => analytics.deleteOwnEventsError = e
      ),
    ];

    for (final (name, step, set) in cases) {
      test('falha em $name: failed(step, offline) e a nova tentativa conclui',
          () async {
        set(const ChatOfflineException());
        await ctl().run(_secret);

        expect(st().phase, DeletePhase.failed);
        expect(st().failure, DeleteFailureKind.offline);
        expect(st().failedStep, step);
        expect(auth.deleteAccountCalls, 0);
        expect(
            st().message, contains('O que já foi apagado continua apagado.'));

        set(null);
        await ctl().run(_secret);
        expect(st().phase, DeletePhase.done);
        expect(auth.deleteAccountCalls, 1);
      });
    }
  });

  test('cota do Spark (resource-exhausted) vira mensagem de tente mais tarde',
      () async {
    events.deleteError = fb('resource-exhausted');
    await ctl().run(_secret);
    expect(st().failure, DeleteFailureKind.quota);
    expect(st().message, deleteQuotaMessage);
  });

  test('permission-denied (regras nao implantadas): unknown, mensagem generica',
      () async {
    social.deleteSentError = fb('permission-denied');
    await ctl().run(_secret);
    expect(st().failure, DeleteFailureKind.unknown);
    expect(st().message, contains('Parte dos seus dados já foi apagada'));
    expect(st().message, isNot(contains('permission')));
  });

  test('requires-recent-login no fim: so repete Auth, sem refazer o Firestore',
      () async {
    auth.deleteAccountError =
        const AuthException(AuthErrorCode.requiresRecentLogin);
    await ctl().run(_secret);

    expect(st().failure, DeleteFailureKind.requiresRecentLogin);
    expect(st().failedStep, DeleteStep.account);
    expect(st().dataDeleted, isTrue);
    expect(st().message,
        'Por segurança, digite sua senha novamente para concluir.');
    final profileDeletes = log.where((e) => e == 'profile.delete').length;
    expect(profileDeletes, 1);
    expect(prefs.getKeys(), contains('astrum.outra')); // ainda nao limpou

    auth.deleteAccountError = null;
    log.clear();
    await ctl().run('nova-senha');

    expect(st().phase, DeletePhase.done);
    expect(
        log, ['reauthenticate', 'deleteAccount', 'account_delete_completed']);
  });

  test(
      'senha errada depois dos dados apagados: mensagem sem "nada foi apagado"',
      () async {
    auth.deleteAccountError =
        const AuthException(AuthErrorCode.requiresRecentLogin);
    await ctl().run(_secret);
    auth.deleteAccountError = null;
    auth.reauthError = const AuthException(AuthErrorCode.invalidCredentials);
    await ctl().run('errada');
    expect(st().message, 'Senha incorreta. Tente de novo.');
  });

  group('troca de usuario na mesma sessao', () {
    test('A conclui, B cadastra e exclui: a cascata de B roda', () async {
      await ctl().run(_secret);
      expect(st().phase, DeletePhase.done);
      expect(st().dataDeleted, isTrue);

      c.read(_testUid.notifier).state = 'u2';
      log.clear();
      await ctl().run(_secret);

      expect(st().phase, DeletePhase.done);
      expect(log, contains('profile.delete'));
      expect(profile.deletedProfiles, ['u1', 'u2']);
    });

    test('A falha em user.delete, sai e B entra: a cascata de B roda',
        () async {
      auth.deleteAccountError = const AuthException(AuthErrorCode.network);
      await ctl().run(_secret);
      expect(st().dataDeleted, isTrue);

      auth.deleteAccountError = null;
      c.read(_testUid.notifier).state = 'u2';
      log.clear();
      await ctl().run(_secret);

      expect(st().phase, DeletePhase.done);
      expect(log, contains('profile.delete'));
      expect(profile.deletedProfiles, ['u1', 'u2']);
    });
  });

  test('perfil ausente: a mesma exclusao funciona (passos sao idempotentes)',
      () async {
    profile.emitMissing('u1');
    await ctl().run(_secret);
    expect(st().phase, DeletePhase.done);
    expect(auth.deleteAccountCalls, 1);
  });

  test('duplo toque: segundo run enquanto roda e ignorado', () async {
    final gate = Completer<void>();
    auth.completerReauth = gate;
    final first = ctl().run(_secret);
    await Future<void>.delayed(Duration.zero);
    expect(st().phase, DeletePhase.running);
    expect(c.read(deletionInFlightProvider), isTrue);

    await ctl().run(_secret); // ignorado
    expect(auth.reauthCalls, hasLength(1));

    gate.complete();
    await first;
    expect(st().phase, DeletePhase.done);
    expect(auth.reauthCalls, hasLength(1));
  });

  test('progresso expoe o passo atual', () async {
    final gate = Completer<void>();
    events.gate = gate;
    final run = ctl().run(_secret);
    await pumpEventQueue();
    expect(st().step, DeleteStep.events);
    gate.complete();
    await run;
  });

  test('senha, texto e uid nao vao para logs nem para o estado', () async {
    final lines = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
    addTearDown(() => debugPrint = old);

    auth.reauthError = const AuthException(AuthErrorCode.invalidCredentials);
    await ctl().run(_secret);
    auth.reauthError = null;
    events.deleteError = fb('unavailable');
    await ctl().run(_secret);

    for (final l in [...lines, st().message ?? '', '${st().failure}']) {
      expect(l, isNot(contains(_secret)));
      expect(l, isNot(contains('u1@example.com')));
    }
    expect(lines, isNotEmpty);
  });
}
