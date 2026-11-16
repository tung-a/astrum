import 'package:astrum/core/analytics/analytics_providers.dart';
import 'package:astrum/core/firebase/paged_delete.dart';
import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/core/storage/prefs_providers.dart';
import 'package:astrum/features/auth/domain/auth_exception.dart';
import 'package:astrum/features/auth/presentation/auth_providers.dart';
import 'package:astrum/features/oracle/presentation/oracle_providers.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:astrum/features/rituals/presentation/rituals_providers.dart';
import 'package:astrum/features/social/presentation/social_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Etapas da exclusao, na ordem em que rodam (docs/architecture/
/// step11-account-deletion.md, secao 4.2).
enum DeleteStep {
  verifying('Verificando…'),
  profile('Apagando seu perfil…'),
  conversations('Apagando conversas…'),
  events('Apagando eventos…'),
  friends('Apagando sua lista de amigos…'),
  notifications('Apagando notificações…'),
  sentIntentions('Apagando intenções enviadas…'),
  usageRecords('Apagando registros de uso…'),
  review('Conferindo…'),
  account('Excluindo o acesso…'),
  cleanup('Limpando este aparelho…');

  const DeleteStep(this.label);
  final String label;
}

enum DeletePhase { idle, running, failed, done }

enum DeleteFailureKind {
  offline,
  quota,
  wrongPassword,
  tooManyRequests,
  requiresRecentLogin,
  unknown,
}

const deleteQuotaMessage = 'O serviço atingiu o limite de hoje. Tente de novo '
    'mais tarde; o que já foi apagado continua apagado.';

class DeleteAccountState {
  const DeleteAccountState({
    this.phase = DeletePhase.idle,
    this.step = DeleteStep.verifying,
    this.failure,
    this.message,
    this.failedStep,
    this.dataDeleted = false,
    this.started = false,
    this.uid,
  });

  final DeletePhase phase;
  final DeleteStep step;
  final DeleteFailureKind? failure;

  /// Texto de erro para a tela (sem senha, sem dado pessoal).
  final String? message;
  final DeleteStep? failedStep;

  /// Todos os dados do Firestore ja foram apagados nesta sessao; so falta o
  /// usuario Auth (retomar so reautentica e exclui a conta).
  final bool dataDeleted;

  /// Ja houve tentativa nesta sessao (decide o texto de "perfil ausente").
  final bool started;

  /// Uid que iniciou a exclusao: `dataDeleted` so vale para ele.
  final String? uid;

  DeleteAccountState copyWith({
    DeletePhase? phase,
    DeleteStep? step,
    DeleteFailureKind? failure,
    String? message,
    DeleteStep? failedStep,
    bool clearFailure = false,
    bool? dataDeleted,
    bool? started,
    String? uid,
  }) =>
      DeleteAccountState(
        phase: phase ?? this.phase,
        step: step ?? this.step,
        failure: clearFailure ? null : failure ?? this.failure,
        message: clearFailure ? null : message ?? this.message,
        failedStep: clearFailure ? null : failedStep ?? this.failedStep,
        dataDeleted: dataDeleted ?? this.dataDeleted,
        started: started ?? this.started,
        uid: uid ?? this.uid,
      );
}

/// Nao e autoDispose: a exclusao continua depois que a tela sai (o router leva
/// ao login quando o usuario Auth some).
final deleteAccountControllerProvider =
    NotifierProvider<DeleteAccountController, DeleteAccountState>(
        DeleteAccountController.new);

/// Orquestra a exclusao da conta (Spark, sem Cloud Functions: a cascata e do
/// cliente). Idempotente e retomavel: cada passo apaga ate uma pagina vazia
/// lida do servidor; repetir `run` termina o trabalho.
///
/// Ordem: reautenticar, checar servidor, apagar `users/{uid}` +
/// `publicProfiles/{uid}` (marcador de "perfil ausente"), subcolecoes,
/// varredura final e, por ultimo, o usuario Auth. Nenhuma senha, texto de
/// conversa ou dado pessoal vai a log, analytics ou excecao.
class DeleteAccountController extends Notifier<DeleteAccountState> {
  @override
  DeleteAccountState build() => const DeleteAccountState();

  void _at(DeleteStep step) => state = state.copyWith(step: step);

  Future<void> run(String password) async {
    if (state.phase == DeletePhase.running) return; // duplo toque
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      _fail(const AuthException(AuthErrorCode.unknown), DeleteStep.verifying);
      return;
    }
    // O estado sobrevive a troca de usuario: nunca reaproveitar o de outro uid.
    if (state.uid != null && state.uid != uid) {
      state = const DeleteAccountState();
    }
    state = state.copyWith(
      uid: uid,
      phase: DeletePhase.running,
      step: DeleteStep.verifying,
      clearFailure: true,
      started: true,
    );
    ref.read(deletionInFlightProvider.notifier).state = true;
    try {
      final auth = ref.read(authRepositoryProvider);
      await auth.reauthenticate(password);
      if (!state.dataDeleted) {
        await _cascade(uid);
        state = state.copyWith(dataDeleted: true);
      }
      _at(DeleteStep.account);
      await auth.deleteAccount();
      _at(DeleteStep.cleanup);
      await _cleanup();
      state = state.copyWith(phase: DeletePhase.done);
    } catch (e) {
      _fail(e, state.step);
    } finally {
      ref.read(deletionInFlightProvider.notifier).state = false;
    }
  }

  Future<void> _cascade(String uid) async {
    final profile = ref.read(profileRepositoryProvider);
    final chat = ref.read(chatRepositoryProvider);
    final events = ref.read(eventsRepositoryProvider);
    final social = ref.read(socialRepositoryProvider);
    final analytics = ref.read(analyticsServiceProvider);

    // Pre-condicoes: nada e apagado se falharem.
    await profile.ensureServerReachable(uid);
    await profile.drainPendingWrites(); // sem prazo estourado: segue
    // Contingencia: limpeza do cache na proxima partida a frio.
    await ref.read(localDataCleanerProvider).markCacheWipePending();

    _at(DeleteStep.profile);
    await profile.deleteProfile(uid);
    _at(DeleteStep.conversations);
    final convIds = await chat.deleteAllConversations(uid);
    _at(DeleteStep.events);
    await events.deleteAllEvents(uid);
    _at(DeleteStep.friends);
    await social.deleteAllFriends(uid);
    _at(DeleteStep.notifications);
    await social.deleteAllReceivedNotifications(uid);
    _at(DeleteStep.sentIntentions);
    await social.deleteSentIntentions(uid);
    _at(DeleteStep.usageRecords);
    await analytics.deleteOwnEvents(uid);

    // Varredura final: pega o que outro aparelho gravou no meio.
    _at(DeleteStep.review);
    for (final id in convIds) {
      await chat.deleteConversation(uid, id);
    }
    await chat.deleteAllConversations(uid);
    await events.deleteAllEvents(uid);
    await social.deleteAllFriends(uid);
    await social.deleteAllReceivedNotifications(uid);
  }

  /// Melhor esforco: o usuario Auth ja foi excluido.
  Future<void> _cleanup() async {
    try {
      // Ja sem login: o servico grava userId 'anonymous' (sem uid/e-mail).
      await ref
          .read(analyticsServiceProvider)
          .logEvent('account_delete_completed');
    } catch (_) {}
    try {
      await ref.read(localDataCleanerProvider).wipeOnAccountEnd();
    } catch (e) {
      debugPrint('exclusao: limpeza local falhou (${e.runtimeType})');
    }
    ref.read(accountDeletedNoticeProvider.notifier).state = true;
  }

  void _fail(Object e, DeleteStep step) {
    final kind = _kindOf(e);
    // So tipo/codigo: nunca senha, texto de conversa ou dado pessoal.
    debugPrint('exclusao: falha em ${step.name} (${_codeOf(e)})');
    state = state.copyWith(
      phase: DeletePhase.failed,
      failure: kind,
      failedStep: step,
      message: deleteFailureMessage(kind,
          dataDeleted: state.dataDeleted,
          partial: step != DeleteStep.verifying || state.dataDeleted),
    );
  }

  static String _codeOf(Object e) {
    if (e is AuthException) return e.code.name;
    if (e is FirebaseException) return e.code;
    return e.runtimeType.toString();
  }

  static DeleteFailureKind _kindOf(Object e) {
    if (e is AuthException) {
      return switch (e.code) {
        AuthErrorCode.invalidCredentials => DeleteFailureKind.wrongPassword,
        AuthErrorCode.tooManyRequests => DeleteFailureKind.tooManyRequests,
        AuthErrorCode.requiresRecentLogin =>
          DeleteFailureKind.requiresRecentLogin,
        AuthErrorCode.network => DeleteFailureKind.offline,
        _ => DeleteFailureKind.unknown,
      };
    }
    if (e is ServerOfflineException) {
      return DeleteFailureKind.offline;
    }
    if (e is FirebaseException) {
      return switch (e.code) {
        'unavailable' || 'deadline-exceeded' => DeleteFailureKind.offline,
        'resource-exhausted' => DeleteFailureKind.quota,
        _ => DeleteFailureKind.unknown,
      };
    }
    return DeleteFailureKind.unknown;
  }
}

/// Texto de erro da exclusao por tipo de falha.
String deleteFailureMessage(DeleteFailureKind kind,
    {bool dataDeleted = false, bool partial = true}) {
  AuthException a(AuthErrorCode c) => AuthException(c);
  return switch (kind) {
    DeleteFailureKind.quota => deleteQuotaMessage,
    DeleteFailureKind.wrongPassword => deleteAccountErrorMessage(
        a(AuthErrorCode.invalidCredentials),
        afterDataDeleted: dataDeleted),
    DeleteFailureKind.tooManyRequests =>
      deleteAccountErrorMessage(a(AuthErrorCode.tooManyRequests)),
    DeleteFailureKind.requiresRecentLogin =>
      deleteAccountErrorMessage(a(AuthErrorCode.requiresRecentLogin)),
    DeleteFailureKind.offline =>
      deleteAccountErrorMessage(a(AuthErrorCode.network), partial: partial),
    DeleteFailureKind.unknown =>
      deleteAccountErrorMessage(a(AuthErrorCode.unknown), partial: partial),
  };
}
